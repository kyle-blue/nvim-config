-- core/git_compare_hl.lua
-- Sets up buffer-level line highlighting, tree row highlighting, and user
-- commands for the two-baseline git comparison system.
-- Called from core/autocmds.lua after plugins load.
--
-- Highlight layers (background tints, full line width):
--   Origin baseline  (merge-base with upstream)  – muted bg tint
--   Accepted baseline (:Accept commit)           – more vivid bg tint
--
-- Commands:
--   :Accept     – pins the current HEAD as the "accepted" baseline
--   :AcceptDiff – opens CodeDiff between current state and the accepted baseline

local M = {}

-- Highlight group definitions ------------------------------------------------
-- All highlights use background colours so text colour is preserved.

local function define_hl_groups()
	-- Tree row backgrounds (full-width, applied via line_hl_group extmarks after
	-- each TreeRendered event – see setup_tree_hl below).
	-- Origin baseline: muted tint
	vim.api.nvim_set_hl(0, "GitCompareOriginNew", { bg = "#192e19" })
	vim.api.nvim_set_hl(0, "GitCompareOriginModified", { bg = "#321900" })
	-- Accepted baseline: more vivid tint
	vim.api.nvim_set_hl(0, "GitCompareAcceptNew", { bg = "#1f4020" })
	vim.api.nvim_set_hl(0, "GitCompareAcceptModified", { bg = "#4a2500" })

	-- Buffer line backgrounds (full-width via line_hl_group extmarks).
	-- Origin layer: very subtle
	vim.api.nvim_set_hl(0, "GitCompareBufOriginNew", { bg = "#121e12" })
	vim.api.nvim_set_hl(0, "GitCompareBufOriginModified", { bg = "#241200" })
	-- Accepted layer: slightly stronger
	vim.api.nvim_set_hl(0, "GitCompareBufAcceptNew", { bg = "#182c18" })
	vim.api.nvim_set_hl(0, "GitCompareBufAcceptModified", { bg = "#361a00" })

	-- Diff stat virtual text colours (bright, no bold so they don't overpower names).
	vim.api.nvim_set_hl(0, "GitCompareStatAdd", { fg = "#00ff44" })
	vim.api.nvim_set_hl(0, "GitCompareStatDel", { fg = "#ff3333" })
	vim.api.nvim_set_hl(0, "GitCompareStatChg", { fg = "#ff9900" })
	-- Sidebar panel header: blue background, bright foreground, bold.
	vim.api.nvim_set_hl(0, "GitComparePanelHeader", { bg = "#003070", fg = "#e8e8ff", bold = true })
	-- Sidebar directory name: bold only (inherits fg/bg from the row highlight).
	vim.api.nvim_set_hl(0, "GitComparePanelFolder", { bold = true })

	-- Make nvim-tree folder names bold (read → modify → write to preserve fg/bg).
	for _, grp in ipairs({
		"NvimTreeFolderName",
		"NvimTreeOpenedFolderName",
		"NvimTreeEmptyFolderName",
	}) do
		local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = grp, link = false })
		if ok then
			hl.bold = true
			pcall(vim.api.nvim_set_hl, 0, grp, hl)
		end
	end
end

-- Buffer highlighting --------------------------------------------------------

local ns = vim.api.nvim_create_namespace("git_compare_hl")

-- Per-buffer cache: skip clear+reapply if highlights haven't changed.
-- Key: bufnr → "gen:origin_flag:accept_flag:linecount"
-- Bumped whenever gc.invalidate_* is called (gen changes) or line count changes.
local _buf_hl_cache = {}

local function buf_hl_hash(bufnr, filepath, gen, origin_status, accept_status)
	local of = origin_status.new[filepath] and "on"
		or origin_status.modified[filepath] and "om"
		or ""
	local af = (accept_status and accept_status.new[filepath]) and "an"
		or (accept_status and accept_status.modified[filepath]) and "am"
		or ""
	return gen .. ":" .. of .. ":" .. af .. ":" .. vim.api.nvim_buf_line_count(bufnr)
end

-- Apply all-line highlight for a file that is entirely new (untracked or added).
local function hl_all_lines(bufnr, hl_group, priority)
	local count = vim.api.nvim_buf_line_count(bufnr)
	for lnum = 0, count - 1 do
		pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, 0, {
			line_hl_group = hl_group,
			priority = priority,
		})
	end
end

local function apply_buf_hl(bufnr)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	if vim.bo[bufnr].buftype ~= "" then
		return
	end
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath == "" then
		return
	end

	local gc = require("git_compare")
	local origin = gc.get_origin_commit()
	local accepted = gc.get_accepted_commit()
	local origin_status = gc.get_file_status(origin)
	local accept_status = gc.get_file_status(accepted)

	-- Skip clear+reapply entirely if nothing has changed since last apply.
	-- This eliminates the two-frame flash caused by clear → render → apply.
	local hash = buf_hl_hash(bufnr, filepath, gc.get_invalidation_gen(), origin_status, accept_status)
	if _buf_hl_cache[bufnr] == hash then
		return
	end
	_buf_hl_cache[bufnr] = hash

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	-- Origin layer – priority 10.
	-- If the file is entirely new (untracked or added since origin), highlight every
	-- line green.  Otherwise fall back to hunk-level diff highlighting.
	if origin then
		if origin_status.new[filepath] then
			hl_all_lines(bufnr, "GitCompareBufOriginNew", 10)
		else
			for _, hunk in ipairs(gc.get_line_hunks(origin, filepath)) do
				local hl = hunk.kind == "new" and "GitCompareBufOriginNew" or "GitCompareBufOriginModified"
				for _, lnum in ipairs(hunk.lines) do
					pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum - 1, 0, {
						line_hl_group = hl,
						priority = 10,
					})
				end
			end
		end
	end

	-- Accepted layer – priority 20 (wins over origin).
	if accepted then
		if accept_status.new[filepath] then
			hl_all_lines(bufnr, "GitCompareBufAcceptNew", 20)
		else
			for _, hunk in ipairs(gc.get_line_hunks(accepted, filepath)) do
				local hl = hunk.kind == "new" and "GitCompareBufAcceptNew" or "GitCompareBufAcceptModified"
				for _, lnum in ipairs(hunk.lines) do
					pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum - 1, 0, {
						line_hl_group = hl,
						priority = 20,
					})
				end
			end
		end
	end
end

local function refresh_all_bufs()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			apply_buf_hl(bufnr)
		end
	end
end

local function reload_tree()
	local ok, api = pcall(require, "nvim-tree.api")
	if ok then
		pcall(api.tree.reload)
	end
end

-- Tree row highlighting ------------------------------------------------------
-- After every TreeRendered event we walk the visible node list in the same DFS
-- order as the renderer and apply a line_hl_group extmark for each entry that
-- has a git-compare status.  line_hl_group fills the FULL ROW background (to
-- the window's right edge) – the decorator API cannot do this.

local tree_ns = vim.api.nvim_create_namespace("git_compare_tree_hl")

local function setup_tree_hl()
	local ok_api, tree_api = pcall(require, "nvim-tree.api")
	if not ok_api then
		return
	end

	-- Ask nvim-tree's internal core module for the first data line (1-based).
	-- Falls back to 2 (root label on line 1, nodes start on line 2).
	local function first_node_line()
		local ok, core = pcall(require, "nvim-tree.core")
		if ok and core.get_nodes_starting_line then
			return core.get_nodes_starting_line()
		end
		return 2
	end

	-- Walk visible nodes in render order, building {[line_1based] = {path, is_dir}}.
	-- Mirrors the Iterator used inside Explorer:get_nodes_by_line().
	local function build_line_map()
		local root = tree_api.tree.get_nodes()
		if not root or not root.nodes then
			return {}
		end

		local line = first_node_line()
		local map = {}

		local function walk(nodes)
			for _, node in ipairs(nodes) do
				if not node.hidden then
					map[line] = {
						path = node.absolute_path,
						is_dir = (node.type == "directory") or (node.nodes ~= nil),
					}
					line = line + 1
					-- Recurse into expanded directories.
					if node.nodes and node.open and #node.nodes > 0 then
						walk(node.nodes)
					end
				end
			end
		end

		walk(root.nodes)
		return map
	end

	tree_api.events.subscribe(tree_api.events.Event.TreeRendered, function(data)
		local bufnr = data and data.bufnr
		if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end

		vim.api.nvim_buf_clear_namespace(bufnr, tree_ns, 0, -1)

		local gc = require("git_compare")
		local origin_commit = gc.get_origin_commit()
		local accept_commit = gc.get_accepted_commit()
		local origin_status = gc.get_file_status(origin_commit)
		local accept_status = gc.get_file_status(accept_commit)

		for line_1, entry in pairs(build_line_map()) do
			local abs_path, is_dir = entry.path, entry.is_dir
			local hl
			local stat_commit
			if accept_commit and accept_status.new[abs_path] then
				hl = "GitCompareAcceptNew"
				stat_commit = accept_commit
			elseif accept_commit and accept_status.modified[abs_path] then
				hl = "GitCompareAcceptModified"
				stat_commit = accept_commit
			elseif origin_status.new[abs_path] then
				hl = "GitCompareOriginNew"
				stat_commit = origin_commit
			elseif origin_status.modified[abs_path] then
				hl = "GitCompareOriginModified"
				stat_commit = origin_commit
			end

			-- Build diff-stat virtual text for changed entries.
			local vt = {}
			if stat_commit then
				if is_dir then
					local s = gc.get_dir_stat(stat_commit, abs_path)
					if s.added > 0 then table.insert(vt, { " +" .. s.added, "GitCompareStatAdd" }) end
					if s.deleted > 0 then table.insert(vt, { " -" .. s.deleted, "GitCompareStatDel" }) end
					if s.changed > 0 then table.insert(vt, { " ~" .. s.changed, "GitCompareStatChg" }) end
				else
					local s = gc.get_file_stat(stat_commit, abs_path)
					if s.added > 0 then table.insert(vt, { " +" .. s.added, "GitCompareStatAdd" }) end
					if s.removed > 0 then table.insert(vt, { " -" .. s.removed, "GitCompareStatDel" }) end
				end
			end

			-- Combine background highlight and virt_text into ONE extmark so the
			-- virtual text is rendered on top of the row tint (not on Normal bg).
			if hl or #vt > 0 then
				local opts = {}
				if hl then opts.line_hl_group = hl end
				if #vt > 0 then
					opts.virt_text = vt
					opts.virt_text_pos = "eol"
				end
				pcall(vim.api.nvim_buf_set_extmark, bufnr, tree_ns, line_1 - 1, 0, opts)
			end
		end
	end)
end

-- Public setup ---------------------------------------------------------------

-- Debounced full-refresh used by the filesystem watcher.
local _refresh_timer = nil
local function debounced_refresh()
	local uv = vim.uv or vim.loop
	if _refresh_timer then
		pcall(function()
			_refresh_timer:stop()
			_refresh_timer:close()
		end)
		_refresh_timer = nil
	end
	_refresh_timer = uv.new_timer()
	_refresh_timer:start(
		800,
		0,
		vim.schedule_wrap(function()
			_refresh_timer = nil
			local gc = require("git_compare")
			gc.invalidate_all()
			refresh_all_bufs()
			reload_tree()
			pcall(function()
				require("git_compare_sidebar").refresh()
			end)
		end)
	)
end

-- Install a libuv file-event watcher on a single path.
local function watch_file(path)
	local uv = vim.uv or vim.loop
	local w = uv.new_fs_event()
	if not w then
		return
	end
	local ok = pcall(function()
		w:start(path, {}, function(err)
			if not err then
				debounced_refresh()
			end
		end)
	end)
	if not ok then
		pcall(function()
			w:stop()
			w:close()
		end)
	end
end

-- Set up a fs watcher on .git/HEAD only (branch switches, commits).
-- We deliberately skip .git/index: it changes on every git read-lock and
-- would fire dozens of times per minute under normal usage, causing constant
-- full refreshes and cursor flicker.
local function setup_git_watchers()
	local git_dir = vim.trim(vim.fn.system("git rev-parse --git-dir 2>/dev/null"))
	if vim.v.shell_error ~= 0 or git_dir == "" then
		return
	end
	if git_dir:sub(1, 1) ~= "/" then
		git_dir = vim.fn.getcwd() .. "/" .. git_dir
	end
	watch_file(git_dir .. "/HEAD") -- fires on commit / branch checkout
end

function M.setup()
	define_hl_groups()

	-- Re-apply highlight groups whenever the colorscheme changes (schedule to
	-- let nvim-tree re-define its groups first).
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("GitCompareHLGroups", { clear = true }),
		callback = function()
			vim.schedule(define_hl_groups)
		end,
	})

	setup_tree_hl()
	setup_git_watchers()

	local augroup = vim.api.nvim_create_augroup("GitCompareHL", { clear = true })

	-- Highlight newly entered / loaded buffers.
	vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost" }, {
		group = augroup,
		callback = function(ev)
			vim.schedule(function()
				apply_buf_hl(ev.buf)
			end)
		end,
	})

	-- After a save, invalidate just that file's cache then re-highlight.
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		callback = function(ev)
			local filepath = vim.api.nvim_buf_get_name(ev.buf)
			require("git_compare").invalidate_file(filepath)
			vim.schedule(function()
				apply_buf_hl(ev.buf)
				reload_tree()
				pcall(function()
					require("git_compare_sidebar").refresh()
				end)
			end)
		end,
	})

	-- When a file is changed externally (e.g. Copilot writes directly to disk).
	vim.api.nvim_create_autocmd({ "FileChangedShellPost" }, {
		group = augroup,
		callback = function(ev)
			require("git_compare").invalidate_file(vim.api.nvim_buf_get_name(ev.buf))
			vim.schedule(function()
				apply_buf_hl(ev.buf)
			end)
		end,
	})

	-- On focus return, drop all caches and repaint.  Limit to one full refresh
	-- per 5 seconds to prevent rapid invalidations when switching windows.
	local _last_focus_invalidation = 0
	vim.api.nvim_create_autocmd("FocusGained", {
		group = augroup,
		callback = function()
			local now = vim.uv and vim.uv.hrtime() or vim.loop.hrtime()
			now = now / 1e9 -- convert ns → seconds
			if now - _last_focus_invalidation < 5 then
				return
			end
			_last_focus_invalidation = now
			vim.schedule(function()
				require("git_compare").invalidate_all()
				refresh_all_bufs()
				reload_tree()
				pcall(function()
					require("git_compare_sidebar").refresh()
				end)
			end)
		end,
	})

	-- For new (untracked) files: re-apply highlight as lines are added.
	-- Debounce per-buffer at 300 ms to avoid firing on every keystroke.
	local _text_changed_timers = {}
	vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
		group = augroup,
		callback = function(ev)
			local bufnr = ev.buf
			if vim.bo[bufnr].buftype ~= "" then
				return
			end
			local fp = vim.api.nvim_buf_get_name(bufnr)
			if fp == "" then
				return
			end
			local gc = require("git_compare")
			local os = gc.get_file_status(gc.get_origin_commit())
			if not os.new[fp] then
				return
			end
			-- Cancel previous timer for this buffer (if any).
			if _text_changed_timers[bufnr] then
				pcall(function()
					_text_changed_timers[bufnr]:stop()
					_text_changed_timers[bufnr]:close()
				end)
				_text_changed_timers[bufnr] = nil
			end
			local uv = vim.uv or vim.loop
			local t = uv.new_timer()
			_text_changed_timers[bufnr] = t
			t:start(300, 0, vim.schedule_wrap(function()
				pcall(function()
					t:stop()
					t:close()
				end)
				_text_changed_timers[bufnr] = nil
				-- Invalidate this file so hash changes and apply_buf_hl runs.
				gc.invalidate_file(fp)
				apply_buf_hl(bufnr)
			end))
		end,
	})

	-- :Accept – snapshot the CURRENT working-tree state as the accepted baseline.
	-- Stores the snapshot under refs/nvim-accept/baseline so it:
	--   • is never GC'd (it's a named ref)
	--   • never appears in `git stash list` (not on refs/stash)
	--   • automatically replaces the previous baseline on the next :Accept
	vim.api.nvim_create_user_command("Accept", function()
		-- Delete any previous baseline ref so the old stash object can eventually GC.
		vim.fn.system("git update-ref -d refs/nvim-accept/baseline 2>/dev/null")

		-- Build a snapshot commit of the current working tree + index.
		local stash_sha = vim.trim(vim.fn.system("git stash create 2>/dev/null"))
		local commit
		if vim.v.shell_error == 0 and stash_sha ~= "" then
			-- Park the stash object under our private ref so it won't be GC'd.
			vim.fn.system("git update-ref refs/nvim-accept/baseline " .. stash_sha)
			commit = stash_sha
		else
			-- Working tree is clean; HEAD is the correct baseline.
			commit = vim.trim(vim.fn.system("git rev-parse HEAD 2>/dev/null"))
			if vim.v.shell_error ~= 0 or commit == "" then
				vim.notify("Accept: not in a git repository", vim.log.levels.ERROR)
				return
			end
			vim.fn.system("git update-ref refs/nvim-accept/baseline " .. commit)
		end

		local gc = require("git_compare")
		gc.set_accepted_commit(commit)
		gc.invalidate_all()
		vim.schedule(function()
			refresh_all_bufs()
			reload_tree()
			pcall(function()
				require("git_compare_sidebar").refresh()
			end)
		end)
		vim.notify("Accepted baseline: " .. commit:sub(1, 8), vim.log.levels.INFO)
	end, { desc = "Snapshot current working-tree state as the accepted baseline" })
	vim.api.nvim_create_user_command("AcceptDiff", function()
		local accepted = require("git_compare").get_accepted_commit()
		if not accepted then
			vim.notify("AcceptDiff: no accepted commit set — run :Accept first", vim.log.levels.WARN)
			return
		end
		vim.cmd("CodeDiff " .. accepted)
	end, { desc = "Show diff between current state and accepted commit (CodeDiff)" })
end

return M
