return {
	"saghen/blink.cmp",
	dependencies = "rafamadriz/friendly-snippets",

	version = "1.*",
	opts_extend = { "sources.default" },

	---@module 'blink.cmp'
	---@type blink.cmp.Config
	opts = {
		completion = {
			list = {
				selection = {
					preselect = true,
					auto_insert = false,
				},
			},
			documentation = {
				auto_show = true,
				auto_show_delay_ms = 50,
				window = {
					border = "rounded",
				},
			},
		},

		appearance = {
			-- Sets the fallback highlight groups to nvim-cmp's highlight groups
			use_nvim_cmp_as_default = true,
			nerd_font_variant = "mono",
		},

		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
		},

		keymap = {
			preset = "default",
			["<Tab>"] = { "select_and_accept", "fallback" },
			["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
		},
	},
}
