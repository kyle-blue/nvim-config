return {
	"olimorris/codecompanion.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-treesitter/nvim-treesitter",
	},
	opts = {
		--Refer to: https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua
		interactions = {
			--NOTE: Change the adapter as required
			chat = { adapter = "copilot" },
			inline = { adapter = "copilot" },
		},
		opts = {
			log_level = "DEBUG",
		},
	},
}
