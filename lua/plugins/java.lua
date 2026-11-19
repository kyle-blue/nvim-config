local function get_java_executable()
	local java_home = os.getenv("JAVA_HOME")
	if java_home and java_home ~= "" then
		local java = java_home .. "/bin/java"
		if vim.fn.executable(java) == 1 then
			return java
		end
	end

	-- Nvim may launch without SDKMAN shell integration so JAVA_HOME might not be set.
	-- Fall back to SDKMAN's default ("current") JDK.
	local java = vim.fn.expand("~/.sdkman/candidates/java/current/bin/java")
	if vim.fn.executable(java) == 1 then
		return java
	end

	return "java"
end

-- Read the major version from a JDK home's `release` file (e.g. JAVA_VERSION="25.0.5").
-- The `release` file also marks a real JDK home, so nil means "not a JDK".
local function jdk_major_version(home)
	local release = home .. "/release"
	if vim.fn.filereadable(release) ~= 1 then
		return nil
	end
	for _, line in ipairs(vim.fn.readfile(release)) do
		local major = line:match('^JAVA_VERSION="(%d+)')
		if major then
			return tonumber(major)
		end
	end
	return nil
end

-- Build jdtls runtime list from SDKMAN-installed JDKs. jdtls rejects duplicate
-- runtime names, so keep one JDK per major version (the newest by dir name).
local function get_sdkman_runtimes()
	local runtimes = {}
	local candidates_dir = vim.fn.expand("~/.sdkman/candidates/java")
	if vim.fn.isdirectory(candidates_dir) ~= 1 then
		return runtimes
	end

	local by_major = {}
	local entries = vim.fn.readdir(candidates_dir)
	table.sort(entries)
	for _, entry in ipairs(entries) do
		if entry ~= "current" then
			local home = candidates_dir .. "/" .. entry
			local major = jdk_major_version(home)
			if major and major >= 11 then
				by_major[major] = home
			end
		end
	end

	for major, home in pairs(by_major) do
		table.insert(runtimes, { name = "JavaSE-" .. major, path = home })
	end
	return runtimes
end

-- Find the top of a Maven multi-module build without relying on mvnw.
-- Starts at the nearest pom.xml and climbs while the parent dir's pom lists
-- the current dir in <modules>. Stops at an unrelated pom above, so the root
-- never escapes into an enclosing project that doesn't own this one.
-- Returns nil only when there is no pom.xml above start_dir at all.
local function maven_aggregator_root(start_dir)
	local pom = vim.fs.find("pom.xml", { upward = true, path = start_dir })[1]
	if not pom then
		return nil
	end
	local dir = vim.fs.dirname(pom)
	while true do
		local parent = vim.fs.dirname(dir)
		local parent_pom = parent .. "/pom.xml"
		if parent == dir or vim.fn.filereadable(parent_pom) == 0 then
			break
		end
		local text = table.concat(vim.fn.readfile(parent_pom), "\n")
		local name = vim.pesc(vim.fs.basename(dir))
		-- <module> is Maven 3; Maven 4 renames it to <subproject>
		local listed = text:find("<module>%s*" .. name .. "%s*</module>")
			or text:find("<subproject>%s*" .. name .. "%s*</subproject>")
		if not listed then
			break
		end
		dir = parent
	end
	return dir
end

-- jdtls only resolves sibling modules against each other when they share one
-- workspace, so the root must be the top of the build, not the nearest module.
-- Order: wrapper / Gradle settings, then the Maven <modules> chain, then a
-- plain build file or .git for anything that isn't a Maven project.
local function find_project_root()
	local buf_name = vim.api.nvim_buf_get_name(0)
	local start_dir = buf_name ~= "" and vim.fs.dirname(buf_name) or vim.fn.getcwd()
	return vim.fs.root(0, { "mvnw", "gradlew", "settings.gradle", "settings.gradle.kts" })
		or maven_aggregator_root(start_dir)
		or vim.fs.root(0, { "build.gradle", "build.gradle.kts", ".git" })
end

local function build_jdtls_config()
	local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/jdtls"
	if vim.fn.executable(mason_bin) ~= 1 then
		vim.notify("jdtls not installed — run :MasonInstall jdtls", vim.log.levels.WARN)
		return nil
	end

	local java_executable = get_java_executable()
	local root_dir = find_project_root()
	-- Key the workspace on the full root path (not the basename) so same-named
	-- projects get separate indexes and any cwd inside a project maps to one workspace.
	local workspace_name = vim.fn.fnamemodify(root_dir or vim.fn.getcwd(), ":p:h"):gsub("[/\\]", "%%")
	local workspace_dir = vim.fn.stdpath("data") .. "/jdtls-workspace/" .. workspace_name

	-- DAP bundles: java-debug-adapter enables breakpoints, java-test enables test running
	local bundles = {}
	local mason_data = vim.fn.stdpath("data") .. "/mason/packages"

	local debug_jar = vim.fn.glob(
		mason_data .. "/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar",
		true
	)
	if debug_jar ~= "" then
		table.insert(bundles, debug_jar)
	end

	-- Skip jars that aren't OSGi bundles (runner, jacoco agent) and the asm bundle jdtls
	-- already ships; loading them fails with "Failed to load extension bundles".
	local test_jars = vim.fn.glob(mason_data .. "/java-test/extension/server/*.jar", true, true)
	for _, jar in ipairs(test_jars) do
		local name = vim.fn.fnamemodify(jar, ":t")
		if
			name ~= "com.microsoft.java.test.runner-jar-with-dependencies.jar"
			and name ~= "jacocoagent.jar"
			and not name:match("^org%.objectweb%.asm_")
		then
			table.insert(bundles, jar)
		end
	end

	local config = {
		cmd = {
			mason_bin,
			"--java-executable",
			java_executable,
			"--jvm-arg=-Xmx2g",
			"-data",
			workspace_dir,
		},

		root_dir = root_dir,

		capabilities = require("blink.cmp").get_lsp_capabilities(),

		settings = {
			java = {
				configuration = {
					runtimes = get_sdkman_runtimes(),
				},
				eclipse = { downloadSources = true },
				maven = { downloadSources = true },
				format = { enabled = true },
				inlayHints = {
					parameterNames = { enabled = "all" },
				},
				signatureHelp = { enabled = true },
				implementationsCodeLens = { enabled = true },
				referencesCodeLens = { enabled = true },
				completion = {
					-- Filter out noise from completion list
					filteredTypes = {
						"com.sun.*",
						"io.micrometer.shaded.*",
						"java.awt.*",
						"jdk.*",
						"sun.*",
					},
				},
				sources = {
					organizeImports = { starThreshold = 9999, staticStarThreshold = 9999 },
				},
			},
		},

		on_attach = function(_, bufnr)
			local jdtls = require("jdtls")
			local map = function(keys, func, desc)
				vim.keymap.set("n", keys, func, { buffer = bufnr, desc = "Java: " .. desc })
			end

			map("<leader>jo", jdtls.organize_imports, "[J]ava [O]rganize Imports")
			map("<leader>jv", jdtls.extract_variable, "[J]ava Extract [V]ariable")
			map("<leader>jc", jdtls.extract_constant, "[J]ava Extract [C]onstant")
			map("<leader>jm", function()
				jdtls.extract_method(true)
			end, "[J]ava Extract [M]ethod")
			map("<leader>ju", jdtls.update_project_config, "[J]ava [U]pdate Project Config")

			-- DAP test keymaps — only available when java-test bundle was loaded
			local ok, jdtls_dap = pcall(require, "jdtls.dap")
			if ok then
				map("<leader>jt", jdtls_dap.test_nearest_method, "[J]ava [T]est Nearest Method")
				map("<leader>jT", jdtls_dap.test_class, "[J]ava [T]est Class")
				map("<leader>jd", jdtls_dap.pick_test, "[J]ava [D]ebug / Pick Test")
			end

			-- Register which-key group name so <leader>j hints are grouped
			local wk_ok, wk = pcall(require, "which-key")
			if wk_ok then
				wk.add({ { "<leader>j", group = "Java", buffer = bufnr } })
			end
		end,
	}

	if #bundles > 0 then
		config.init_options = { bundles = bundles }
	end

	return config
end

return {
	{
		"mfussenegger/nvim-jdtls",
		ft = "java",
		dependencies = {
			"williamboman/mason.nvim",
			"saghen/blink.cmp",
		},
		config = function()
			local function start()
				local cfg = build_jdtls_config()
				if cfg then
					require("jdtls").start_or_attach(cfg)
				end
			end

			-- Autocmd handles every Java buffer opened after this plugin loaded.
			-- start() below handles the buffer that triggered the initial ft=java load.
			vim.api.nvim_create_autocmd("FileType", {
				pattern = "java",
				group = vim.api.nvim_create_augroup("JavaJdtls", { clear = true }),
				callback = start,
			})

			start()
		end,
	},
}
