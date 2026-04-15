return {
	"nvim-tree/nvim-tree.lua",
	version = "*",
	lazy = false,
	dependencies = {
		{ "nvim-tree/nvim-web-devicons", opts = {} },
	},

	keys = {
		{ "\\", "<Cmd>NvimTreeToggle<CR>", desc = "Toggle NvimTree" },
		-- Also <leader>tr to reset to cwd root (tree root). Config below
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

			vim.keymap.set("n", "<leader>tr", function()
				print(vim.fn.getcwd())
				api.tree.change_root(vim.fn.getcwd())
				api.tree.reload()
			end, {
				desc = "Reset Root to CWD",
				buffer = bufnr,
				noremap = true,
				silent = true,
			})

			vim.keymap.set("n", "<leader>.", function()
				api.filter.dotfiles.toggle()
				api.filter.git.ignored.toggle()
			end, {
				desc = "Toggle Hidden/Gitignored Files",
				buffer = bufnr,
				noremap = true,
				silent = true,
			})

			vim.keymap.set("n", "<leader>sr", function()
				local node = api.tree.get_node_under_cursor()
				if not node then
					return
				end

				-- If it's a file, get its parent folder; if it's a folder, use it directly
				local path = node.type == "directory" and node.absolute_path
					or vim.fn.fnamemodify(node.absolute_path, ":h")

				vim.api.nvim_set_current_dir(path)
				api.tree.change_root(path)
				print("New CWD: " .. path)
			end, { desc = "Set CWD to Cursor Node", buffer = bufnr })
		end

		-- Initialize nvim-tree with the custom on_attach
		require("nvim-tree").setup({
			on_attach = my_on_attach,
			hijack_netrw = false,
			disable_netrw = false,

			-- Fix needed to prevent nvim-tree messing with vim root dir
			actions = {
				change_dir = {
					enable = false,
					global = false,
				},
			},
			view = {
				width = 30,
				side = "left",
			},
			filters = {
				dotfiles = false,
				git_ignored = false,
			},
		})
	end,
}
