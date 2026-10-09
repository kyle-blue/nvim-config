local keymap = vim.keymap

-- Quality of life

keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR><Esc>", { desc = "Clear search highlights and escape" })

-- Visual mode

keymap.set("v", ">", ">gv", { desc = "Stay in visual mode after indent" })
keymap.set("v", "<", "<gv", { desc = "Stay in visual mode after unindent" })

keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Code

vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostic [Q]uickfix list" })
vim.keymap.set("i", "<M-BS>", "<C-w>", { desc = "Delete word backward" })

-- Clipboard
vim.keymap.set("n", "<leader>cp", function()
	vim.fn.setreg("+", vim.fn.expand("%"))
end, { desc = "Copy relative file path" })

vim.keymap.set("n", "<leader>cP", function()
	vim.fn.setreg("+", vim.fn.expand("%:p"))
end, { desc = "Copy absolute file path" })

-- <leader>cf copies the absolute file path straight away, then listens briefly
-- for modifiers: d = directory instead, r = relative to the cwd.
local function next_key(ms)
	local c = 0
	vim.wait(ms, function()
		c = vim.fn.getchar(0)
		return c ~= 0
	end, 10)
	if c == 0 then
		return nil
	end
	return type(c) == "number" and vim.fn.nr2char(c) or c
end

local function copy_path(dir, relative)
	local path = vim.fn.expand("%:p")
	if path == "" then
		path = vim.fn.getcwd()
		dir = true
	elseif dir then
		path = vim.fn.fnamemodify(path, ":h")
	end
	if relative then
		path = vim.fs.relpath(vim.fn.getcwd(), path) or path
	end
	vim.fn.setreg("+", path)
	vim.notify("Copied " .. path)
end

vim.keymap.set("n", "<leader>cf", function()
	copy_path(false, false)
	local key = next_key(500)
	local dir = key == "d"
	if dir then
		copy_path(true, false)
		key = next_key(500)
	end
	if key == "r" then
		copy_path(dir, true)
	elseif key then
		vim.api.nvim_feedkeys(key, "t", false)
	end
end, { desc = "Copy file path (+d directory, +r relative)" })
