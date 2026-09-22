return {
	{
		"romus204/tree-sitter-manager.nvim",
		dependencies = {}, -- tree-sitter CLI must be installed system-wide
		config = function()
			require("tree-sitter-manager").setup({
				ensure_installed = {
					"bash",
					"c",
					"diff",
					"html",
					"java",
					"lua",
					"luadoc",
					"markdown",
					"markdown_inline",
					"query",
					"vim",
					"vimdoc",
					"svelte",
					"angular",
					"typescript",
					"css",
					"scss",
				},
				auto_install = true,
				-- Only accepts true or a list of languages; starts treesitter for every installed parser
				highlight = true,
			})

			-- The plugin matches filetype to parser name, so htmlangular needs starting manually
			vim.treesitter.language.register("angular", "htmlangular")

			vim.api.nvim_create_autocmd("FileType", {
				pattern = "htmlangular",
				callback = function()
					vim.treesitter.start()
				end,
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-context",
		config = function()
			require("treesitter-context").setup({
				enable = true,
				multiline_threshold = 20,
				trim_scope = "outer",
				mode = "cursor",
				separator = nil,
				zindex = 20,
			})
		end,
	},
}
