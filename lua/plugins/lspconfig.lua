---@global
---@desc This variable is defined externally
Snacks = nil

return {
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			{ "williamboman/mason.nvim", config = true },
			"williamboman/mason-lspconfig.nvim",
			"WhoIsSethDaniel/mason-tool-installer.nvim", -- For formatters/linters
			{ "folke/lazydev.nvim", ft = "lua", opts = {} },
			"saghen/blink.cmp",
		},
		config = function()
			-- 1. Setup LSPs
			local servers = {
				html = {},
				cssls = {},
				ts_ls = {},
				-- Only attaches inside Angular workspaces (see lua/angular.lua)
				angularls = {
					filetypes = { "typescript", "htmlangular" },
					root_dir = function(bufnr, on_dir)
						local root = require("angular").root(vim.api.nvim_buf_get_name(bufnr))
						if root then
							on_dir(root)
						end
					end,
				},
				gopls = {},
				lemminx = {}, -- XML
				rust_analyzer = {},
				ruff = {}, -- Ruff has a native LSP for diagnostics
				pyright = {
					settings = { pyright = { disableOrganizeImports = true } },
				},
				biome = {},
				lua_ls = {
					settings = {
						Lua = {
							-- Stop lua_ls from complaining about Neovim globals
							diagnostics = {
								globals = { "vim", "Snacks" },
							},
							completion = { callSnippet = "Replace" },
						},
					},
				},
			}

			-- mason-lspconfig v2 dropped the `handlers` option, so per-server
			-- config must be registered directly via vim.lsp.config.
			vim.lsp.config("*", {
				capabilities = require("blink.cmp").get_lsp_capabilities(),
			})
			for server_name, server_opts in pairs(servers) do
				vim.lsp.config(server_name, server_opts)
			end

			require("mason-lspconfig").setup({
				ensure_installed = vim.tbl_keys(servers),
				-- jdtls is managed by nvim-jdtls (java.lua); auto-enabling it here
				-- attaches a second, unconfigured jdtls client to every Java buffer
				automatic_enable = { exclude = { "jdtls" } },
			})

			-- 2. Setup Formatters and Linters to auto-install
			require("mason-tool-installer").setup({
				ensure_installed = {
					"stylua",
					"prettier", -- Angular (fallback when prettierd is missing)
					"prettierd", -- Angular: daemonised prettier, ~40ms per format once warm
					-- Java: jdtls is the LSP; the other two add DAP and test running support
					"jdtls",
					"java-debug-adapter",
					"java-test",
				},
			})

			-- 3. Buffer-local keymaps
			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
				callback = function(event)
					local client = vim.lsp.get_client_by_id(event.data.client_id)
					local map = function(keys, func, desc, mode)
						vim.keymap.set(mode or "n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
					end

					-- Snacks Picker Keymaps
					map("gd", function()
						Snacks.picker.lsp_definitions()
					end, "[G]oto [D]efinition")
					map("gr", function()
						Snacks.picker.lsp_references()
					end, "[G]oto [R]eferences")
					map("gI", function()
						Snacks.picker.lsp_implementations()
					end, "[G]oto [I]mplementation")
					map("<leader>ds", function()
						Snacks.picker.lsp_symbols()
					end, "[D]ocument [S]ymbols")
					map("<leader>ws", function()
						Snacks.picker.lsp_workspace_symbols()
					end, "[W]orkspace [S]ymbols")

					map("<leader>rn", function()
						-- angularls renames across TS and templates; letting ts_ls also run would apply edits twice
						local angular = vim.lsp.get_clients({ bufnr = event.buf, name = "angularls" })[1]
						vim.lsp.buf.rename(nil, angular and { name = "angularls" } or nil)
					end, "[R]e[n]ame Symbol")
					map("<leader>ra", vim.lsp.buf.code_action, "[R]efactor [A]ctions", { "n", "x" })

					-- Inlay Hints
					if
						client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf)
					then
						map("<leader>th", function()
							vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }))
						end, "[T]oggle Inlay [H]ints")
					end
				end,
			})
		end,
	},
}
