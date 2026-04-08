return {
	"folke/tokyonight.nvim",
	priority = 1000,
	config = function()
		---@diagnostic disable-next-line: missing-fields
		require("tokyonight").setup({
			styles = {
				comments = { italic = false }, -- Disable italics in comments
			},
			style = "night",
			sidebars = "dark",

			on_highlights = function(hg, colors)
				hg.LineNr = {
					fg = "#946d03",
				}
				hg.LineNrBelow = {
					fg = "#946d03",
				}
				hg.LineNrAbove = {
					fg = "#946d03",
				}
			end,
		})

		vim.cmd.colorscheme("tokyonight-night")
	end,
}
