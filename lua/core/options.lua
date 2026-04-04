local opt = vim.opt

-- Global Settings
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- UI & Appearance
opt.laststatus = 3 -- one status bar no matter how many windows
opt.number = true
opt.relativenumber = true
opt.termguicolors = true
opt.signcolumn = "yes"
opt.cursorline = true -- Highlight line of cursor
opt.scrolloff = 4
opt.showmode = false -- Don't show mode as this is displayed in statusbar now -- Don't show mode as this is displayed in statusbar now

-- Splitting
opt.splitbelow = true
opt.splitright = true

-- Tabs & indentation
opt.tabstop = 4
opt.shiftwidth = 4
opt.autoindent = true
opt.smartindent = true
opt.expandtab = true
opt.wrap = false
-- This is commonly overriden in opt_local by built in file-type plugins, so we also override this in autocmds.lua
opt.formatoptions:remove({"r", "o"}) -- Stop comments auto starting on new line

-- Completion
opt.pumheight = 10
opt.pumblend = 10
-- menuone: show even if one menu item and don't immediately select first
-- noselect: don't auto hover on first
-- noinsert: don't actually show text in buffer until selected
opt.completeopt = { "menuone", "noselect", "noinsert" }

-- Search patterns
opt.ignorecase = true
opt.smartcase = true -- No ignorecase when there is an uppercase

-- Behaviour
opt.mouse = "a" -- Can use mouse in all modes
opt.clipboard = "" -- Save to + register for system clipboard, more control
opt.updatetime = 250 -- Faster UI (plugins use CursorHold event. This controls when it fires)
opt.timeoutlen = 300 -- When to give up on key mappings (ms)
opt.undofile = true

-- Swap and recovery
local swap_dir = os.getenv("HOME") .. "/.local/share/nvim/swap"

if vim.fn.isdirectory(swap_dir) == 0 then
    vim.fn.mkdir(swap_dir, "p")
end

opt.directory = swap_dir .. "//"
