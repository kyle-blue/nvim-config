local function get_java_executable()
	local java_home = os.getenv("JAVA_HOME")
	if java_home and java_home ~= "" then
		local java = java_home .. "/bin/java"
		if vim.fn.executable(java) == 1 then
			return java
		end
	end

	-- Nvim may launch without jenv shell integration so JAVA_HOME might not be set.
	-- Call jenv directly to resolve the active version.
	local jenv_bin = vim.fn.expand("~/.jenv/bin/jenv")
	if vim.fn.executable(jenv_bin) == 1 then
		local result = vim.fn.system(jenv_bin .. " java-home 2>/dev/null")
		if vim.v.shell_error == 0 then
			local home = vim.trim(result)
			if home ~= "" then
				local java = home .. "/bin/java"
				if vim.fn.executable(java) == 1 then
					return java
				end
			end
		end
	end

	return "java"
end

-- Build jdtls runtime list from jenv managed versions.
-- Only considers major-version dirs (e.g. "17", "25") to avoid duplicates.
local function get_jenv_runtimes()
	local runtimes = {}
	local versions_dir = vim.fn.expand("~/.jenv/versions")
	if vim.fn.isdirectory(versions_dir) ~= 1 then
		return runtimes
	end

	for _, entry in ipairs(vim.fn.readdir(versions_dir)) do
		local major = entry:match("^(%d+)$")
		if major and tonumber(major) >= 11 then
			local path = versions_dir .. "/" .. entry
			if vim.fn.isdirectory(path) == 1 then
				table.insert(runtimes, {
					name = "JavaSE-" .. major,
					path = path,
				})
			end
		end
	end

	return runtimes
end

local function build_jdtls_config()
	local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/jdtls"
	if vim.fn.executable(mason_bin) ~= 1 then
		vim.notify("jdtls not installed — run :MasonInstall jdtls", vim.log.levels.WARN)
		return nil
	end

	local java_executable = get_java_executable()
	local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
	local workspace_dir = vim.fn.stdpath("data") .. "/jdtls-workspace/" .. project_name

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

	local test_jars = vim.fn.glob(mason_data .. "/java-test/extension/server/*.jar", true, true)
	if type(test_jars) == "table" then
		vim.list_extend(bundles, test_jars)
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

		root_dir = require("jdtls.setup").find_root({ "gradlew", "mvnw", "pom.xml", "build.gradle", ".git" }),

		capabilities = require("blink.cmp").get_lsp_capabilities(),

		settings = {
			java = {
				configuration = {
					runtimes = get_jenv_runtimes(),
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
