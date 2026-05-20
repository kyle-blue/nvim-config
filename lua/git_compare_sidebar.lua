-- git_compare_sidebar.lua
-- Three-panel left sidebar alongside nvim-tree:
--
--   ┌────────────────────┐
--   │  nvim-tree  (~50%) │
--   ├────────────────────┤
--   │  Origin Changes    │  files changed since branch merge-base
--   │        (~25%)      │
--   ├────────────────────┤
--   │  Accept Changes    │  files changed since last :Accept baseline
--   │        (~25%)      │
--   └────────────────────┘
--
-- <CR> / o on a folder → expand/collapse
-- <CR> / o on a file   → open in the nearest editor window
--
-- NOTE: nvim-tree is a per-tab singleton; its renderer is not exposed as a
-- reusable library, so we implement expand/collapse natively here.

local M = {}

local sidebar_ns = vim.api.nvim_create_namespace("git_compare_sidebar")

local state = {
origin_win = nil,
origin_buf = nil,
accept_win = nil,
accept_buf = nil,
-- lnum_1based → { abs_path, is_dir }
origin_node_data = {},
accept_node_data = {},
-- nil = open (default), false = explicitly collapsed
origin_dir_open = {},
accept_dir_open = {},
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function find_tree_win()
for _, win in ipairs(vim.api.nvim_list_wins()) do
if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "NvimTree" then
return win
end
end
end

local function make_panel_buf(label)
local buf = vim.api.nvim_create_buf(false, true)
vim.bo[buf].buftype = "nofile"
vim.bo[buf].bufhidden = "wipe"
vim.bo[buf].swapfile = false
vim.bo[buf].filetype = "git_compare_panel"
pcall(vim.api.nvim_buf_set_name, buf, "GitCompare:" .. label)
return buf
end

local function setup_panel_win(win)
local wo = vim.wo[win]
wo.number = false
wo.relativenumber = false
wo.signcolumn = "no"
wo.foldcolumn = "0"
wo.wrap = false
wo.winfixheight = true
wo.winfixwidth = true
wo.statusline = " "
wo.winhl = "Normal:NvimTreeNormal,NormalNC:NvimTreeNormalNC,EndOfBuffer:NvimTreeEndOfBuffer"
end

-- ── Path-tree builder ─────────────────────────────────────────────────────────

local function build_path_tree(abs_paths, git_root)
local norm_root = git_root:gsub("/$", "")
local root = { children = {}, is_dir = true, abs_path = norm_root }
for _, abs in ipairs(abs_paths) do
local norm = abs:gsub("/$", "")
if norm:sub(1, #norm_root) == norm_root then
local rel = norm:sub(#norm_root + 2)
if rel and rel ~= "" then
local parts = {}
for p in rel:gmatch("[^/]+") do
table.insert(parts, p)
end
local node = root
for i, part in ipairs(parts) do
if not node.children[part] then
node.children[part] = {
name = part,
abs_path = norm_root .. "/" .. table.concat(parts, "/", 1, i),
is_dir = (i < #parts),
children = {},
}
end
node = node.children[part]
end
end
end
end
return root
end

-- ── Highlight helper ──────────────────────────────────────────────────────────

local function get_hl(abs_path, origin_status, accept_status)
if accept_status.new[abs_path] then
return "GitCompareAcceptNew"
elseif accept_status.modified[abs_path] then
return "GitCompareAcceptModified"
elseif origin_status.new[abs_path] then
return "GitCompareOriginNew"
elseif origin_status.modified[abs_path] then
return "GitCompareOriginModified"
end
end

-- ── Tree renderer ─────────────────────────────────────────────────────────────
-- dir_open: { abs_path = true } means expanded; nil/missing = collapsed (default).

local function render_tree(root, origin_status, accept_status, dir_open)
local lines = {}
local highlights = {}
local node_data = {} -- lnum_1based → { abs_path, is_dir }

local function walk(node, pfx)
local children = {}
for _, c in pairs(node.children) do
table.insert(children, c)
end
table.sort(children, function(a, b)
if a.is_dir ~= b.is_dir then
return a.is_dir
end
return a.name < b.name
end)

for i, child in ipairs(children) do
local last = (i == #children)
local connector = last and "└ " or "├ "
local child_pfx = pfx .. (last and "  " or "│ ")
local is_open = child.is_dir and (dir_open[child.abs_path] == true)
local icon = child.is_dir and (is_open and "▾ " or "▸ ") or ""
local text = pfx .. connector .. icon .. child.name .. (child.is_dir and "/" or "")

table.insert(lines, text)
local lnum = #lines

local hl = get_hl(child.abs_path, origin_status, accept_status)
if hl then
table.insert(highlights, { lnum_0 = lnum - 1, hl = hl })
end

node_data[lnum] = { abs_path = child.abs_path, is_dir = child.is_dir }

if child.is_dir and is_open and next(child.children) then
walk(child, child_pfx)
end
end
end

walk(root, "")
return lines, highlights, node_data
end

-- ── Panel writer ──────────────────────────────────────────────────────────────

local function write_panel(bufnr, header, lines, highlights, offset)
if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
return
end
local sep = string.rep("─", 28)
local content = { header, sep }
for _, l in ipairs(lines) do
table.insert(content, l)
end

vim.bo[bufnr].modifiable = true
pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, content)
vim.bo[bufnr].modifiable = false

vim.api.nvim_buf_clear_namespace(bufnr, sidebar_ns, 0, -1)
for _, h in ipairs(highlights) do
pcall(vim.api.nvim_buf_set_extmark, bufnr, sidebar_ns, h.lnum_0 + offset, 0, {
line_hl_group = h.hl,
})
end
end

-- ── Path collection ───────────────────────────────────────────────────────────

local function collect_paths(file_list)
local seen, paths = {}, {}
for p in pairs(file_list.new) do
if not seen[p] then
seen[p] = true
table.insert(paths, p)
end
end
for p in pairs(file_list.modified) do
if not seen[p] then
seen[p] = true
table.insert(paths, p)
end
end
table.sort(paths)
return paths
end

-- ── Public refresh ────────────────────────────────────────────────────────────

function M.refresh()
local any = (state.origin_buf and vim.api.nvim_buf_is_valid(state.origin_buf))
or (state.accept_buf and vim.api.nvim_buf_is_valid(state.accept_buf))
if not any then
return
end

local gc = require("git_compare")
local git_root = gc.git_root()
if not git_root then
return
end

local origin_commit = gc.get_origin_commit()
local accept_commit = gc.get_accepted_commit()
local origin_fl = gc.get_changed_file_list(origin_commit)
local accept_fl = gc.get_changed_file_list(accept_commit)
local origin_status = gc.get_file_status(origin_commit)
local accept_status = gc.get_file_status(accept_commit)

local HEADER_LINES = 2

if state.origin_buf and vim.api.nvim_buf_is_valid(state.origin_buf) then
local paths = collect_paths(origin_fl)
local tree = build_path_tree(paths, git_root)
local lines, hls, node_data =
render_tree(tree, origin_status, accept_status, state.origin_dir_open)
write_panel(state.origin_buf, " Origin Changes", lines, hls, HEADER_LINES)
state.origin_node_data = {}
for lnum, d in pairs(node_data) do
state.origin_node_data[lnum + HEADER_LINES] = d
end
end

if state.accept_buf and vim.api.nvim_buf_is_valid(state.accept_buf) then
local paths = collect_paths(accept_fl)
local tree = build_path_tree(paths, git_root)
local lines, hls, node_data =
render_tree(tree, origin_status, accept_status, state.accept_dir_open)
write_panel(state.accept_buf, " Accept Changes", lines, hls, HEADER_LINES)
state.accept_node_data = {}
for lnum, d in pairs(node_data) do
state.accept_node_data[lnum + HEADER_LINES] = d
end
end
end

-- ── Keymaps ───────────────────────────────────────────────────────────────────

local function open_file_in_editor(path)
for _, win in ipairs(vim.api.nvim_list_wins()) do
local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
if ft ~= "NvimTree" and ft ~= "git_compare_panel" then
vim.api.nvim_set_current_win(win)
break
end
end
vim.cmd("edit " .. vim.fn.fnameescape(path))
end

local function attach_keymaps(bufnr, get_node_data, get_dir_open)
local function on_activate()
local lnum = vim.api.nvim_win_get_cursor(0)[1]
local node = get_node_data()[lnum]
if not node then
return
end
if node.is_dir then
local dir_open = get_dir_open()
-- nil = collapsed (default); true = expanded
dir_open[node.abs_path] = (dir_open[node.abs_path] == true) and nil or true
M.refresh()
else
open_file_in_editor(node.abs_path)
end
end

local opts = { buffer = bufnr, noremap = true, silent = true }
vim.keymap.set("n", "<CR>", on_activate, opts)
vim.keymap.set("n", "o", on_activate, opts)
end

-- ── Window management ─────────────────────────────────────────────────────────

function M.close_panels()
for _, k in ipairs({ "origin_win", "accept_win" }) do
if state[k] and vim.api.nvim_win_is_valid(state[k]) then
pcall(vim.api.nvim_win_close, state[k], true)
end
state[k] = nil
end
state.origin_buf = nil
state.accept_buf = nil
state.origin_node_data = {}
state.accept_node_data = {}
end

-- Open two panel windows below nvim-tree, CONFINED to the tree column.
-- Uses nvim_open_win with win= (Neovim 0.10+) so the splits never escape the
-- tree column and never push the global statusline.
local function create_panels()
local tree_win = find_tree_win()
if not tree_win then
return
end

M.close_panels()

local total = vim.api.nvim_win_get_height(tree_win)
local tree_h = math.max(8, math.floor(total * 0.50))
local panel_h = math.max(4, math.floor(total * 0.25))

local origin_buf = make_panel_buf("origin")
local accept_buf = make_panel_buf("accept")

-- Create both splits without heights first; Neovim distributes equally by
-- default. We then set explicit heights to get reliable 50/25/25 ratios.
local ok1, err1 = pcall(function()
origin_win = vim.api.nvim_open_win(origin_buf, false, {
win = tree_win,
split = "below",
})
end)
if not ok1 then
vim.notify("git_compare_sidebar: nvim_open_win failed: " .. tostring(err1), vim.log.levels.WARN)
return
end

local accept_win
local ok2, err2 = pcall(function()
accept_win = vim.api.nvim_open_win(accept_buf, false, {
win = origin_win,
split = "below",
})
end)
if not ok2 then
vim.notify("git_compare_sidebar: nvim_open_win failed: " .. tostring(err2), vim.log.levels.WARN)
return
end

-- Set all three heights now that both splits exist.
-- winfixheight (applied in setup_panel_win) will lock the panel heights.
vim.api.nvim_win_set_height(tree_win, tree_h)
vim.api.nvim_win_set_height(origin_win, panel_h)
-- accept_win gets the remaining space (≈ panel_h)

setup_panel_win(origin_win)
state.origin_win = origin_win
state.origin_buf = origin_buf

setup_panel_win(accept_win)
state.accept_win = accept_win
state.accept_buf = accept_buf

attach_keymaps(
origin_buf,
function() return state.origin_node_data end,
function() return state.origin_dir_open end
)
attach_keymaps(
accept_buf,
function() return state.accept_node_data end,
function() return state.accept_dir_open end
)

vim.schedule(M.refresh)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
local ok, tree_api = pcall(require, "nvim-tree.api")
if not ok then
return
end

tree_api.events.subscribe(tree_api.events.Event.TreeOpen, function()
vim.schedule(create_panels)
end)

tree_api.events.subscribe(tree_api.events.Event.TreeClose, function()
M.close_panels()
end)
end

return M
