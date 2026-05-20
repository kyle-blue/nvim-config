return {
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		opts = {
			-- Increase ibl debounce from default 200ms.
			-- ibl fires debounced_refresh on every WinScrolled; 200ms means the guides
			-- only refresh once scroll activity stops.
			debounce = 200,
		},
	},
}
