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
