return {
	{
		"petertriho/nvim-scrollbar",
		config = function()
			local colors = require("tokyonight.colors").setup()

			require("scrollbar").setup({
				handle = {
					color = colors.bg_highlight,
				},
				marks = {
					Search = { color = colors.orange },
					Error = { color = colors.error },
					Warn = { color = colors.warning },
					Info = { color = colors.info },
					Hint = { color = colors.hint },
					Misc = { color = colors.purple },
					-- git_compare tier 1 (origin): dimmer green / amber
					GitCompareOriginNew      = { text = "▌", color = "#00cc66", priority = 8 },
					GitCompareOriginModified = { text = "▌", color = "#cc6600", priority = 8 },
					-- git_compare tier 2 (accept): brighter — same as gutter bar signs
					GitCompareAcceptNew      = { text = "▌", color = "#00ffaa", priority = 9 },
					GitCompareAcceptModified = { text = "▌", color = "#ffaa00", priority = 9 },
				},
			})
		end,
	},
}
