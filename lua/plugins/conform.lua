local function uses_prettier(bufnr)
	local ft = vim.bo[bufnr].filetype
	return ft == "htmlangular"
		or (ft == "typescript" and require("angular").root(vim.api.nvim_buf_get_name(bufnr)) ~= nil)
end

return {
	"stevearc/conform.nvim",
	event = { "BufWritePre" },
	cmd = { "ConformInfo" },
	keys = {
		{
			"<leader>f",
			function()
				require("conform").format({ async = true, lsp_format = "fallback" })
			end,
			mode = "",
			desc = "[F]ormat buffer",
		},
	},
	opts = {
		formatters_by_ft = {
			lua = { "stylua" },
			javascript = { "biome-check" },
			-- Biome leaves Angular's inline `template`/`styles` untouched; prettier formats them as HTML/CSS
			typescript = function(bufnr)
				if require("angular").root(vim.api.nvim_buf_get_name(bufnr)) then
					return { "prettierd", "prettier", stop_after_first = true }
				end
				return { "biome-check" }
			end,
			javascriptreact = { "biome-check" },
			typescriptreact = { "biome-check" },
			json = { "biome-check" },
			jsonc = { "biome-check" },
			css = { "biome-check" },
			svelte = { "biome" },
			htmlangular = { "prettierd_angular", "prettier_angular", stop_after_first = true },
			-- Go and Rust fall back to gopls/rust_analyzer via lsp_format fallback
		},
		formatters = {
			-- Newer Angular templates (app.html) aren't named *.component.html, so prettier can't infer the parser
			prettier_angular = {
				inherit = "prettier",
				append_args = { "--parser", "angular" },
			},
			-- prettierd takes no CLI flags, so pose as a *.component.html file (same dir keeps config lookup intact)
			prettierd_angular = {
				inherit = "prettierd",
				args = function(_, ctx)
					if ctx.filename:match("%.component%.html$") then
						return { ctx.filename }
					end
					return { (ctx.filename:gsub("%.html$", ".component.html")) }
				end,
			},
		},
		-- Prettier-formatted Angular buffers format asynchronously after save (the daemon's first start takes ~1s)
		format_on_save = function(bufnr)
			if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat or uses_prettier(bufnr) then
				return
			end
			return { timeout_ms = 500, lsp_format = "fallback" }
		end,
		format_after_save = function(bufnr)
			if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat or not uses_prettier(bufnr) then
				return
			end
			return { lsp_format = "fallback" }
		end,
	},
	init = function()
		vim.api.nvim_create_user_command("FormatDisable", function(args)
			if args.bang then
				vim.b.disable_autoformat = true
			else
				vim.g.disable_autoformat = true
			end
		end, { desc = "Disable autoformat-on-save", bang = true })

		vim.api.nvim_create_user_command("FormatEnable", function()
			vim.b.disable_autoformat = false
			vim.g.disable_autoformat = false
		end, { desc = "Re-enable autoformat-on-save" })
	end,
}
