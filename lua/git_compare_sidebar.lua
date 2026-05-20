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

-- Maps row hl group → tint suffix for combined stat+bg highlight groups.
local HL_TINT_SUFFIX = {
GitCompareOriginNew      = "OriginNew",
GitCompareOriginModified = "OriginModified",
GitCompareAcceptNew      = "AcceptNew",
GitCompareAcceptModified = "AcceptModified",
}

local function stat_hl(stat_type, row_hl)
local suffix = HL_TINT_SUFFIX[row_hl]
if suffix then return "GitCompareStat" .. stat_type .. suffix end
return "GitCompareStat" .. stat_type
end

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

-- Tracks the last NvimTree / git_compare_panel window the user was in so that
-- <C-w>h from an editor window returns to it rather than always jumping to the
-- topmost left pane (nvim-tree).
local _last_left_win = nil

-- Persists the left-panel position across NvimTree open/close cycles.
-- { win_type = "nvimtree"|"origin"|"accept", lnum = N }
local _saved_left_pos = nil

local function win_type(win)
if not (win and vim.api.nvim_win_is_valid(win)) then return nil end
local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
if ft == "NvimTree" then return "nvimtree" end
if ft == "git_compare_panel" then
local bufnr = vim.api.nvim_win_get_buf(win)
if bufnr == state.origin_buf then return "origin" end
if bufnr == state.accept_buf then return "accept" end
end
return nil
end

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
wo.signcolumn = "yes:1"
wo.foldcolumn = "0"
wo.wrap = false
wo.winfixheight = true
wo.winfixwidth = true
wo.statusline = " "
-- Map StatusLine to the panel background so the separator between panels is invisible.
wo.winhl = "Normal:NvimTreeNormal,NormalNC:NvimTreeNormalNC,EndOfBuffer:NvimTreeEndOfBuffer"
.. ",StatusLine:NvimTreeNormal,StatusLineNC:NvimTreeNormal"
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
-- commit: the baseline commit for this panel (used to fetch diff stats).

local function render_tree(root, origin_status, accept_status, dir_open, commit)
local lines = {}
-- Each entry: { lnum_0, line_hl=str|nil, vt=list|nil }
-- Combined into ONE extmark so virt_text inherits the row's bg tint.
local extmarks = {}
-- Bold ranges for directory names: { lnum_0, col_s, col_e } (byte offsets).
local bold_names = {}
local node_data = {} -- lnum_1based → { abs_path, is_dir }

local gc_mod = nil -- lazy-load git_compare only if needed
local function gc()
if not gc_mod then gc_mod = require("git_compare") end
return gc_mod
end

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
local lnum_0 = lnum - 1

node_data[lnum] = { abs_path = child.abs_path, is_dir = child.is_dir }

local hl = get_hl(child.abs_path, origin_status, accept_status)

-- Diff stats virtual text (same extmark as bg so bg colour is consistent).
local vt = {}
if commit then
if child.is_dir then
local s = gc().get_dir_stat(commit, child.abs_path)
if s.added > 0 then table.insert(vt, { " +" .. s.added, stat_hl("Add", hl) }) end
if s.deleted > 0 then table.insert(vt, { " -" .. s.deleted, stat_hl("Del", hl) }) end
if s.changed > 0 then table.insert(vt, { " ~" .. s.changed, stat_hl("Chg", hl) }) end
else
local s = gc().get_file_stat(commit, child.abs_path)
if s.added > 0 then table.insert(vt, { " +" .. s.added, stat_hl("Add", hl) }) end
if s.removed > 0 then table.insert(vt, { " -" .. s.removed, stat_hl("Del", hl) }) end
end
end

if hl or #vt > 0 then
table.insert(extmarks, {
lnum_0 = lnum_0,
line_hl = hl,
vt = #vt > 0 and vt or nil,
})
end

-- Bold range for the directory name (byte offsets of child.name in the line).
-- connector = "└ "/"├ " (4 bytes each), icon = "▾ "/"▸ " (4 bytes each).
if child.is_dir then
local col_s = #pfx + #connector + #icon
local col_e = col_s + #child.name
table.insert(bold_names, { lnum_0 = lnum_0, col_s = col_s, col_e = col_e })
end

if child.is_dir and is_open and next(child.children) then
walk(child, child_pfx)
end
end
end

walk(root, "")
return lines, extmarks, node_data, bold_names
end

-- ── Panel writer ──────────────────────────────────────────────────────────────

local HEADER_LINES = 1 -- just the title line; no separator line below it

local function write_panel(bufnr, header, lines, extmarks, bold_names)
if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
return
end
local content = { header }
for _, l in ipairs(lines) do
table.insert(content, l)
end

vim.bo[bufnr].modifiable = true
pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, content)
vim.bo[bufnr].modifiable = false

vim.api.nvim_buf_clear_namespace(bufnr, sidebar_ns, 0, -1)

-- Header: blue background highlight across the full width.
pcall(vim.api.nvim_buf_set_extmark, bufnr, sidebar_ns, 0, 0, {
line_hl_group = "GitComparePanelHeader",
})

-- Combined background + virt_text; accept-tier also gets a gutter bar.
for _, e in ipairs(extmarks) do
local opts = {}
if e.line_hl then opts.line_hl_group = e.line_hl end
if e.vt then
opts.virt_text = e.vt
opts.virt_text_pos = "eol"
end
if e.line_hl == "GitCompareAcceptNew" then
opts.sign_text = "▌"
opts.sign_hl_group = "GitCompareAcceptNewSign"
elseif e.line_hl == "GitCompareAcceptModified" then
opts.sign_text = "▌"
opts.sign_hl_group = "GitCompareAcceptModifiedSign"
end
pcall(vim.api.nvim_buf_set_extmark, bufnr, sidebar_ns, e.lnum_0 + HEADER_LINES, 0, opts)
end

-- Bold directory names (inline highlight on the name's byte range).
for _, b in ipairs(bold_names) do
pcall(vim.api.nvim_buf_set_extmark, bufnr, sidebar_ns, b.lnum_0 + HEADER_LINES, b.col_s, {
end_col = b.col_e,
hl_group = "GitComparePanelFolder",
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

if state.origin_buf and vim.api.nvim_buf_is_valid(state.origin_buf) then
local paths = collect_paths(origin_fl)
local tree = build_path_tree(paths, git_root)
local lines, extmarks, node_data, bold_names =
render_tree(tree, origin_status, accept_status, state.origin_dir_open, origin_commit)
write_panel(state.origin_buf, " Origin Changes", lines, extmarks, bold_names)
state.origin_node_data = {}
for lnum, d in pairs(node_data) do
state.origin_node_data[lnum + HEADER_LINES] = d
end
end

if state.accept_buf and vim.api.nvim_buf_is_valid(state.accept_buf) then
local paths = collect_paths(accept_fl)
local tree = build_path_tree(paths, git_root)
local lines, extmarks, node_data, bold_names =
render_tree(tree, origin_status, accept_status, state.accept_dir_open, accept_commit)
write_panel(state.accept_buf, " Accept Changes", lines, extmarks, bold_names)
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

local function attach_keymaps(bufnr, panel_type, get_node_data, get_dir_open)
local function on_activate()
local lnum = vim.api.nvim_win_get_cursor(0)[1]
local node = get_node_data()[lnum]
if not node then
return
end
if node.is_dir then
local dir_open = get_dir_open()
-- Explicit if/else because `and nil or true` silently fails when the
-- "true branch" value is nil (Lua ternary pitfall).
if dir_open[node.abs_path] == true then
dir_open[node.abs_path] = nil -- collapse
else
dir_open[node.abs_path] = true -- expand
end
M.refresh()
else
open_file_in_editor(node.abs_path)
end
end

local opts = { buffer = bufnr, noremap = true, silent = true }
vim.keymap.set("n", "<CR>", on_activate, opts)
vim.keymap.set("n", "o", on_activate, opts)

-- Track cursor position continuously so it can be restored after tree reopen.
-- Also enforces the header-skip rule (cursor must not rest on line 1).
vim.api.nvim_create_autocmd({ "CursorMoved", "WinEnter" }, {
buffer = bufnr,
callback = function()
if vim.api.nvim_buf_line_count(bufnr) > 1 then
local row = vim.api.nvim_win_get_cursor(0)[1]
if row == 1 then
vim.api.nvim_win_set_cursor(0, { 2, 0 })
row = 2
end
_saved_left_pos = { win_type = panel_type, lnum = row }
end
end,
})
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
-- _saved_left_pos is intentionally kept so the next open can restore it.
_last_left_win = nil
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
local bottom_h = math.max(6, total - tree_h)
-- Origin gets 7/12 of the bottom half, accept gets the remaining 5/12.
local origin_h = math.max(3, math.floor(bottom_h * 7 / 12))
-- accept_h is the remainder (set implicitly after origin_h is locked)

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
vim.api.nvim_win_set_height(origin_win, origin_h)
-- accept_win gets the remaining space (≈ bottom_h - origin_h)

setup_panel_win(origin_win)
state.origin_win = origin_win
state.origin_buf = origin_buf

setup_panel_win(accept_win)
state.accept_win = accept_win
state.accept_buf = accept_buf

attach_keymaps(
origin_buf,
"origin",
function() return state.origin_node_data end,
function() return state.origin_dir_open end
)
attach_keymaps(
accept_buf,
"accept",
function() return state.accept_node_data end,
function() return state.accept_dir_open end
)

vim.schedule(function()
M.refresh()
-- Use defer_fn (150ms) instead of vim.schedule so the restore fires
-- reliably AFTER nvim-tree finishes all its own async focus management.
-- Two nested vim.schedule calls were not enough; nvim-tree re-grabs focus
-- on a later event-loop tick.
vim.defer_fn(function()
local pos = _saved_left_pos
if not pos then return end
local target_win, target_buf
if pos.win_type == "origin" and state.origin_win and vim.api.nvim_win_is_valid(state.origin_win) then
target_win = state.origin_win
target_buf = state.origin_buf
elseif pos.win_type == "accept" and state.accept_win and vim.api.nvim_win_is_valid(state.accept_win) then
target_win = state.accept_win
target_buf = state.accept_buf
elseif pos.win_type == "nvimtree" then
target_win = find_tree_win()
end
if not target_win then return end
local buf_to_count = target_buf or vim.api.nvim_win_get_buf(target_win)
local line_count = vim.api.nvim_buf_line_count(buf_to_count)
local lnum = math.min(pos.lnum, math.max(1, line_count))
if target_buf and lnum < HEADER_LINES + 1 then lnum = HEADER_LINES + 1 end
pcall(vim.api.nvim_win_set_cursor, target_win, { lnum, 0 })
_last_left_win = target_win
-- Move focus to origin/accept panels; for nvim-tree leave it where it is.
if pos.win_type == "origin" or pos.win_type == "accept" then
pcall(vim.api.nvim_set_current_win, target_win)
end
end, 150)
end)
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

-- ── Track last focused left-panel window ─────────────────────────────────
local augroup = vim.api.nvim_create_augroup("GitCompareSidebarNav", { clear = true })
vim.api.nvim_create_autocmd("WinEnter", {
group = augroup,
callback = function()
local win = vim.api.nvim_get_current_win()
local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
if ft == "NvimTree" or ft == "git_compare_panel" then
_last_left_win = win
end
end,
})
-- Track nvim-tree cursor position for restoration on reopen.
vim.api.nvim_create_autocmd("CursorMoved", {
group = augroup,
callback = function()
local win = vim.api.nvim_get_current_win()
if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "NvimTree" then
_saved_left_pos = { win_type = "nvimtree", lnum = vim.api.nvim_win_get_cursor(win)[1] }
end
end,
})

-- ── Smart <C-w>h: return to the last focused left-panel window ───────────
-- Falls back to the built-in wincmd h when already in the left column or
-- when no left window has been visited yet.
local function smart_left()
local cur_ft = vim.bo[vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())].filetype
if cur_ft ~= "NvimTree" and cur_ft ~= "git_compare_panel"
and _last_left_win and vim.api.nvim_win_is_valid(_last_left_win) then
vim.api.nvim_set_current_win(_last_left_win)
else
vim.cmd("wincmd h")
end
end
vim.keymap.set("n", "<C-w>h", smart_left, { noremap = true, silent = true, desc = "Go to last focused left panel" })
vim.keymap.set("n", "<C-w><C-h>", smart_left, { noremap = true, silent = true, desc = "Go to last focused left panel" })
end

return M
