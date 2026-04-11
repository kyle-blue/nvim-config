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
				gopls = {},
				rust_analyzer = {},
				ruff = {}, -- Ruff has a native LSP for diagnostics
				pyright = {
					settings = { pyright = { disableOrganizeImports = true } },
				},
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

			require("mason-lspconfig").setup({
				ensure_installed = vim.tbl_keys(servers),
				automatic_enable = true,
				automatic_installation = true,
				handlers = {
					function(server_name)
						local server_opts = servers[server_name] or {}
						server_opts.capabilities = require("blink.cmp").get_lsp_capabilities(server_opts.capabilities)
						vim.lsp.config(server_name, server_opts)
						vim.lsp.enable(server_name)
					end,
				},
			})

			-- 2. Setup Formatters and Linters to auto-install
			require("mason-tool-installer").setup({
				ensure_installed = {
					"prettier",
					"stylua",
					"eslint_d",
				},
			})

			-- 3. Buffer-local keymaps
			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
				callback = function(event)
					local client = vim.lsp.get_client_by_id(event.data.client_id)
					local map = function(keys, func, desc)
						vim.keymap.set("n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
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

					map("<leader>rn", vim.lsp.buf.rename, "[R]e[n]ame Symbol")
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
