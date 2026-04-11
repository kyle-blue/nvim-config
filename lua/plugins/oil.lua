return {
	"stevearc/oil.nvim",
	---@module 'oil'
	---@type oil.SetupOpts
	opts = {
		delete_to_trash = false,
		default_file_explorer = true,

		float = {
			border = "rounded",
			padding = 2,
			max_width = 80,
			max_height = 20,
		},
	},
	dependencies = { { "nvim-mini/mini.icons", opts = {} } },
	lazy = false,
}
