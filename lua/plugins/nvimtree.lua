return {
	"nvim-tree/nvim-tree.lua",
	version = "*",
	lazy = false,
	dependencies = {
		{ "nvim-tree/nvim-web-devicons", opts = {} },
	},

	config = function()
		local tree_api = require("nvim-tree.api")

		-- Session-sticky width: follows manual resizes of the tree window.
		local tree_width = 30

		local function tree_win()
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if
					vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "NvimTree"
					and vim.api.nvim_win_get_config(win).relative == ""
				then
					return win
				end
			end
		end

		vim.api.nvim_create_autocmd("WinResized", {
			group = vim.api.nvim_create_augroup("NvimTreeStickyWidth", { clear = true }),
			callback = function()
				local win = tree_win()
				-- A tree that fills the screen is alone in its tab, not resized by the user.
				if win and vim.api.nvim_win_get_width(win) < vim.o.columns then
					tree_width = vim.api.nvim_win_get_width(win)
				end
			end,
		})

		-- ── Current file highlight ───────────────────────────────────────────
		local current_ns = vim.api.nvim_create_namespace("nvim_tree_current_file")
		local current_file = nil

		local function set_current_file_hl()
			vim.api.nvim_set_hl(0, "NvimTreeCurrentFile", { bg = "#1f2a48" })
			vim.api.nvim_set_hl(0, "NvimTreeCurrentFileName", { fg = "#7dcfff", bold = true })
		end
		set_current_file_hl()

		local function mark_current_file()
			local win = tree_win()
			if not win then
				return
			end
			local bufnr = vim.api.nvim_win_get_buf(win)
			vim.api.nvim_buf_clear_namespace(bufnr, current_ns, 0, -1)
			if not current_file then
				return
			end
			pcall(function()
				local explorer = require("nvim-tree.core").get_explorer()
				local node = explorer and explorer:get_node_from_path(current_file)
				local lnum = explorer and explorer:find_node_line(node) or -1
				if lnum < 1 then
					return
				end
				local text = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
				local name_col = (text:find(node.name, 1, true) or 1) - 1
				-- Low priority so git-compare row tints win; the name styling still shows.
				vim.api.nvim_buf_set_extmark(bufnr, current_ns, lnum - 1, 0, {
					line_hl_group = "NvimTreeCurrentFile",
					priority = 100,
				})
				vim.api.nvim_buf_set_extmark(bufnr, current_ns, lnum - 1, name_col, {
					end_col = #text,
					hl_group = "NvimTreeCurrentFileName",
					priority = 5000,
				})
			end)
		end

		local current_augroup = vim.api.nvim_create_augroup("NvimTreeCurrentFile", { clear = true })
		vim.api.nvim_create_autocmd("BufEnter", {
			group = current_augroup,
			callback = function(args)
				local name = vim.api.nvim_buf_get_name(args.buf)
				if vim.bo[args.buf].buftype ~= "" or name == "" then
					return
				end
				current_file = vim.uv.fs_realpath(name)
				mark_current_file()
			end,
		})
		vim.api.nvim_create_autocmd("ColorScheme", { group = current_augroup, callback = set_current_file_hl })
		tree_api.events.subscribe(tree_api.events.Event.TreeRendered, mark_current_file)

		-- Opening reveals the current file (parents expanded, cursor on it) when it
		-- lives under the cwd; otherwise the tree opens as it was left. With
		-- :DiffToggle on, the sidebar restores its own remembered position instead.
		vim.keymap.set("n", "\\", function()
			local path = vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0))
			local cwd = vim.uv.fs_realpath(vim.fn.getcwd())
			local ok, sidebar = pcall(require, "git_compare_sidebar")
			local reveal = not (ok and sidebar.enabled)
				and path ~= nil
				and cwd ~= nil
				and vim.bo.buftype == ""
				and vim.startswith(path, cwd .. "/")
			tree_api.tree.toggle({ find_file = reveal, focus = true })
		end, { desc = "Toggle NvimTree" })
		-- Also <leader>tr to reset to cwd root (tree root). Config below

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
				width = function()
					return tree_width
				end,
				side = "left",
			},
			filters = {
				dotfiles = false,
				git_ignored = false,
			},
			renderer = {},
		})
	end,
}
