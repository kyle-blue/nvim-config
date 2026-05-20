return {
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		opts = {
			-- Default debounce is 200ms which fires on every WinScrolled.
			-- Increase to 500ms so indent guides only refresh after scrolling stops.
			debounce = 500,
		},
	},
}
