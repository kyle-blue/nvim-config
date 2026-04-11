return {
	"nvim-tree/nvim-tree.lua",
	version = "*",
	lazy = false,
	dependencies = {
		{ "nvim-mini/mini.icons", opts = {} },
	},

	keys = {
		{ "\\", "<Cmd>NvimTreeToggle<CR>", desc = "Toggle NvimTree" },
	},

	config = function()
		local function my_on_attach(bufnr)
			local api = require("nvim-tree.api")

			api.map.on_attach.default(bufnr)

			vim.keymap.set("n", "<leader>o", function()
				local node = api.tree.get_node_under_cursor()
				if not node then
					return
				end

				local path = node.absolute_path

				if node.type == "file" then
					path = vim.fn.fnamemodify(path, ":h")
				end

				require("oil").open_float(path)
			end, {
				desc = "Open Oil Float from NvimTree",
				buffer = bufnr,
				noremap = true,
				silent = true,
			})
		end

		-- Initialize nvim-tree with the custom on_attach
		require("nvim-tree").setup({
			on_attach = my_on_attach,
			hijack_netrw = false,
			disable_netrw = false,

			view = {
				width = 30,
				side = "left",
			},
			filters = {
				dotfiles = false,
			},
		})
	end,
}
