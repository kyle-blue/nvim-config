-- core/git_compare_hl.lua
-- Buffer-level and nvim-tree row highlighting for the two-baseline git comparison system.
--
-- Performance design:
--   • All git I/O is async (via git_compare.warm_async).  No vim.fn.system() here.
--   • apply_buf_hl() calls warm_line_hunks_async → never blocks the main thread.
--   • A single debounced schedule_refresh() (400 ms) collapses all event triggers
--     into one pass; prevents redundant re-renders when multiple events fire together.
--   • Only buffers visible in a window are repainted (not every loaded buffer).
--   • Per-buffer hash guards: highlights are not reapplied if nothing changed.
--   • Signcolumn for nvim-tree is set once on TreeOpen, not on every render.

local M = {}

-- ── Highlight group definitions ──────────────────────────────────────────────

local function define_hl_groups()
	vim.api.nvim_set_hl(0, "GitCompareOriginNew",      { bg = "#192e19" })
	vim.api.nvim_set_hl(0, "GitCompareOriginModified", { bg = "#321900" })
	vim.api.nvim_set_hl(0, "GitCompareAcceptNew",      { bg = "#1f4020" })
	vim.api.nvim_set_hl(0, "GitCompareAcceptModified", { bg = "#4a2500" })

	vim.api.nvim_set_hl(0, "GitCompareBufOriginNew",      { bg = "#121e12" })
	vim.api.nvim_set_hl(0, "GitCompareBufOriginModified", { bg = "#241200" })
	vim.api.nvim_set_hl(0, "GitCompareBufAcceptNew",      { bg = "#182c18" })
	vim.api.nvim_set_hl(0, "GitCompareBufAcceptModified", { bg = "#361a00" })

	vim.api.nvim_set_hl(0, "GitCompareStatAdd", { fg = "#00ff44" })
	vim.api.nvim_set_hl(0, "GitCompareStatDel", { fg = "#ff3333" })
	vim.api.nvim_set_hl(0, "GitCompareStatChg", { fg = "#ff9900" })

	local stat_defs = { { "Add", "#00ff44" }, { "Del", "#ff3333" }, { "Chg", "#ff9900" } }
	local tint_bgs  = {
		{ "OriginNew",      "#192e19" }, { "OriginModified", "#321900" },
		{ "AcceptNew",      "#1f4020" }, { "AcceptModified", "#4a2500" },
	}
	for _, s in ipairs(stat_defs) do
		for _, t in ipairs(tint_bgs) do
			vim.api.nvim_set_hl(0, "GitCompareStat" .. s[1] .. t[1], { fg = s[2], bg = t[2] })
		end
	end

	vim.api.nvim_set_hl(0, "GitCompareAcceptNewSign",         { fg = "#00ffaa", bg = "#1f4020" })
	vim.api.nvim_set_hl(0, "GitCompareAcceptModifiedSign",    { fg = "#ffaa00", bg = "#4a2500" })
	vim.api.nvim_set_hl(0, "GitCompareBufAcceptNewSign",      { fg = "#00ffaa" })
	vim.api.nvim_set_hl(0, "GitCompareBufAcceptModifiedSign", { fg = "#ffaa00" })

	vim.api.nvim_set_hl(0, "GitComparePanelHeader", { bg = "#003070", fg = "#e8e8ff", bold = true })
	vim.api.nvim_set_hl(0, "GitComparePanelFolder", { bold = true })

	for _, grp in ipairs({ "NvimTreeFolderName", "NvimTreeOpenedFolderName", "NvimTreeEmptyFolderName" }) do
		local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = grp, link = false })
		if ok then hl.bold = true; pcall(vim.api.nvim_set_hl, 0, grp, hl) end
	end
end

-- ── Buffer highlighting ───────────────────────────────────────────────────────

local ns = vim.api.nvim_create_namespace("git_compare_hl")

local _buf_hl_cache = {}  -- bufnr → hash string

local function buf_hl_hash(bufnr, filepath, file_gen, origin_status, accept_status)
	local of = origin_status.new[filepath] and "on" or origin_status.modified[filepath] and "om" or ""
	local af = (accept_status and accept_status.new[filepath]) and "an"
		or (accept_status and accept_status.modified[filepath]) and "am" or ""
	-- file_gen is per-file (not global) so only this file's hash changes on save.
	return file_gen .. ":" .. of .. ":" .. af .. ":" .. vim.api.nvim_buf_line_count(bufnr)
end

-- Apply buffer highlights from cache.  Never calls git directly.
-- Must be called after warm_async has completed.
-- Uses set-new-then-delete-old so there is never a zero-highlight frame.
local function apply_buf_hl_from_cache(bufnr)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
	if vim.bo[bufnr].buftype ~= "" then return end
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath == "" then return end

	local gc = require("git_compare")
	local origin   = gc.get_origin_commit()
	local accepted = gc.get_accepted_commit()
	local origin_status = gc.get_file_status(origin)
	local accept_status = gc.get_file_status(accepted)

	local hash = buf_hl_hash(bufnr, filepath, gc.get_file_gen(filepath), origin_status, accept_status)
	if _buf_hl_cache[bufnr] == hash then return end
	_buf_hl_cache[bufnr] = hash

	-- Collect old extmark IDs before applying new ones.
	local old_marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})

	-- Apply all new extmarks first (old ones remain visible in the meantime).
	local new_ids = {}
	local function set(lnum, opts)
		local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, 0, opts)
		if ok then new_ids[id] = true end
	end

	if origin then
		if origin_status.new[filepath] then
			local count = vim.api.nvim_buf_line_count(bufnr)
			for lnum = 0, count - 1 do
				set(lnum, { line_hl_group = "GitCompareBufOriginNew", priority = 10 })
			end
		else
			for _, hunk in ipairs(gc.get_line_hunks(origin, filepath)) do
				local hl = hunk.kind == "new" and "GitCompareBufOriginNew" or "GitCompareBufOriginModified"
				for _, lnum in ipairs(hunk.lines) do
					set(lnum - 1, { line_hl_group = hl, priority = 10 })
				end
			end
		end
	end

	if accepted then
		if accept_status.new[filepath] then
			local count = vim.api.nvim_buf_line_count(bufnr)
			for lnum = 0, count - 1 do
				set(lnum, { line_hl_group = "GitCompareBufAcceptNew", priority = 20,
					sign_text = "▌", sign_hl_group = "GitCompareBufAcceptNewSign" })
			end
		else
			for _, hunk in ipairs(gc.get_line_hunks(accepted, filepath)) do
				local hl      = hunk.kind == "new" and "GitCompareBufAcceptNew"      or "GitCompareBufAcceptModified"
				local sign_hl = hunk.kind == "new" and "GitCompareBufAcceptNewSign"  or "GitCompareBufAcceptModifiedSign"
				for _, lnum in ipairs(hunk.lines) do
					set(lnum - 1, { line_hl_group = hl, priority = 20,
						sign_text = "▌", sign_hl_group = sign_hl })
				end
			end
		end
	end

	-- Delete only the old extmarks that weren't just replaced.
	for _, mark in ipairs(old_marks) do
		if not new_ids[mark[1]] then
			pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark[1])
		end
	end
end

-- Public entry-point used by git_compare.lua's get_line_hunks() lazy-load.
function M.apply_buf(bufnr)
	apply_buf_hl_from_cache(bufnr)
end

-- Warms line-hunks for the current file then applies highlights.
-- Completely non-blocking.
local function apply_buf_hl(bufnr)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
	if vim.bo[bufnr].buftype ~= "" then return end
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath == "" then return end

	local gc = require("git_compare")
	local origin   = gc.get_origin_commit()
	local accepted = gc.get_accepted_commit()

	-- Fast path: hash tells us nothing has changed.
	local origin_status = gc.get_file_status(origin)
	local accept_status = gc.get_file_status(accepted)
	local hash = buf_hl_hash(bufnr, filepath, gc.get_file_gen(filepath), origin_status, accept_status)
	if _buf_hl_cache[bufnr] == hash then return end

	-- Need hunks for modified files – warm async, apply when ready.
	local remaining = 0
	local function done()
		remaining = remaining - 1
		if remaining == 0 then
			apply_buf_hl_from_cache(bufnr)
			pcall(function() require("scrollbar.handlers").show() end)
		end
	end

	if origin and not origin_status.new[filepath] then
		remaining = remaining + 1
		gc.warm_line_hunks_async(origin, filepath, done)
	end
	if accepted and not accept_status.new[filepath] then
		remaining = remaining + 1
		gc.warm_line_hunks_async(accepted, filepath, done)
	end
	if remaining == 0 then
		apply_buf_hl_from_cache(bufnr)
		pcall(function() require("scrollbar.handlers").show() end)
	end
end

-- Only refresh buffers that are currently visible in some window.
local function refresh_visible_bufs()
	local seen = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local bufnr = vim.api.nvim_win_get_buf(win)
		if not seen[bufnr] then
			seen[bufnr] = true
			apply_buf_hl(bufnr)
		end
	end
	-- Refresh scrollbar marks for the active buffer after highlights settle.
	pcall(function() require("scrollbar.handlers").show() end)
end

-- ── Debounced refresh coordinator ────────────────────────────────────────────
-- All event callbacks funnel here.  Debounced at 400 ms so rapid consecutive
-- events (save → watcher → focus) collapse into a single refresh pass.
--
-- invalidate_fn is called LAZILY inside the timer callback (not immediately) so
-- file_status is never blank during the debounce window — old highlights remain
-- visible until the new git data is ready.

local _refresh_timer = nil
local _pending_invalidations = {}  -- collected lazily until timer fires

local function schedule_refresh(invalidate_fn)
	local uv = vim.uv or vim.loop
	if _refresh_timer then
		pcall(function() _refresh_timer:stop(); _refresh_timer:close() end)
		_refresh_timer = nil
	end
	if invalidate_fn then table.insert(_pending_invalidations, invalidate_fn) end
	_refresh_timer = uv.new_timer()
	_refresh_timer:start(400, 0, vim.schedule_wrap(function()
		_refresh_timer = nil
		-- Run all queued invalidations right before the fetch begins.
		local fns = _pending_invalidations
		_pending_invalidations = {}
		for _, fn in ipairs(fns) do fn() end
		local gc = require("git_compare")
		-- Flush stale file-status caches (preserves origin_commit — no extra git spawn).
		-- Callers that need a full reset (invalidate_all, HEAD change) already cleared
		-- origin_commit inside their invalidation function above.
		gc.flush_file_status_caches()
		gc.warm_async(function()
			refresh_visible_bufs()
			-- Reload the tree (triggers TreeRendered which reapplies extmarks).
			local ok, api = pcall(require, "nvim-tree.api")
			if ok then pcall(api.tree.reload) end
			pcall(function() require("git_compare_sidebar").refresh() end)
		end)
	end))
end

-- ── nvim-tree row highlighting ────────────────────────────────────────────────

local tree_ns = vim.api.nvim_create_namespace("git_compare_tree_hl")

local HL_TINT_SUFFIX = {
	GitCompareOriginNew      = "OriginNew",  GitCompareOriginModified = "OriginModified",
	GitCompareAcceptNew      = "AcceptNew",  GitCompareAcceptModified = "AcceptModified",
}
local function stat_hl(stat_type, row_hl)
	local suffix = HL_TINT_SUFFIX[row_hl]
	return suffix and ("GitCompareStat" .. stat_type .. suffix) or ("GitCompareStat" .. stat_type)
end

local function setup_tree_hl()
	local ok_api, tree_api = pcall(require, "nvim-tree.api")
	if not ok_api then return end

	local function first_node_line()
		local ok, core = pcall(require, "nvim-tree.core")
		if ok and core.get_nodes_starting_line then return core.get_nodes_starting_line() end
		return 2
	end

	local function build_line_map()
		local root = tree_api.tree.get_nodes()
		if not root or not root.nodes then return {} end
		local line = first_node_line()
		local map = {}
		local function walk(nodes)
			for _, node in ipairs(nodes) do
				if not node.hidden then
					map[line] = { path = node.absolute_path, is_dir = (node.type == "directory") or (node.nodes ~= nil) }
					line = line + 1
					if node.nodes and node.open and #node.nodes > 0 then walk(node.nodes) end
				end
			end
		end
		walk(root.nodes)
		return map
	end

	-- Set sign column once when the tree opens; not on every render.
	tree_api.events.subscribe(tree_api.events.Event.TreeOpen, function(data)
		vim.schedule(function()
			local bufnr = data and data.bufnr
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				local wbuf = vim.api.nvim_win_get_buf(win)
				if (bufnr and wbuf == bufnr) or vim.bo[wbuf].filetype == "NvimTree" then
					pcall(function() vim.wo[win].signcolumn = "yes:1" end)
					break
				end
			end
		end)
	end)

	tree_api.events.subscribe(tree_api.events.Event.TreeRendered, function(data)
		local bufnr = data and data.bufnr
		if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

		vim.api.nvim_buf_clear_namespace(bufnr, tree_ns, 0, -1)

		local gc = require("git_compare")
		local origin_commit = gc.get_origin_commit()
		local accept_commit = gc.get_accepted_commit()
		local origin_status = gc.get_file_status(origin_commit)
		local accept_status = gc.get_file_status(accept_commit)

		for line_1, entry in pairs(build_line_map()) do
			local abs_path, is_dir = entry.path, entry.is_dir
			local hl, stat_commit
			if accept_commit and accept_status.new[abs_path] then
				hl = "GitCompareAcceptNew";      stat_commit = accept_commit
			elseif accept_commit and accept_status.modified[abs_path] then
				hl = "GitCompareAcceptModified"; stat_commit = accept_commit
			elseif origin_status.new[abs_path] then
				hl = "GitCompareOriginNew";      stat_commit = origin_commit
			elseif origin_status.modified[abs_path] then
				hl = "GitCompareOriginModified"; stat_commit = origin_commit
			end

			local vt = {}
			if stat_commit then
				if is_dir then
					local s = gc.get_dir_stat(stat_commit, abs_path)
					if s.added   > 0 then table.insert(vt, { " +" .. s.added,   stat_hl("Add", hl) }) end
					if s.deleted > 0 then table.insert(vt, { " -" .. s.deleted, stat_hl("Del", hl) }) end
					if s.changed > 0 then table.insert(vt, { " ~" .. s.changed, stat_hl("Chg", hl) }) end
				else
					local s = gc.get_file_stat(stat_commit, abs_path)
					if s.added   > 0 then table.insert(vt, { " +" .. s.added,   stat_hl("Add", hl) }) end
					if s.removed > 0 then table.insert(vt, { " -" .. s.removed, stat_hl("Del", hl) }) end
				end
			end

			if hl or #vt > 0 then
				local opts = {}
				if hl then opts.line_hl_group = hl end
				if #vt > 0 then opts.virt_text = vt; opts.virt_text_pos = "eol" end
				if     hl == "GitCompareAcceptNew"      then opts.sign_text = "▌"; opts.sign_hl_group = "GitCompareAcceptNewSign"
				elseif hl == "GitCompareAcceptModified" then opts.sign_text = "▌"; opts.sign_hl_group = "GitCompareAcceptModifiedSign"
				elseif hl == "GitCompareOriginNew"      then opts.sign_text = " "; opts.sign_hl_group = "GitCompareOriginNew"
				elseif hl == "GitCompareOriginModified" then opts.sign_text = " "; opts.sign_hl_group = "GitCompareOriginModified"
				end
				pcall(vim.api.nvim_buf_set_extmark, bufnr, tree_ns, line_1 - 1, 0, opts)
			end
		end
	end)
end

-- ── File-system watcher ───────────────────────────────────────────────────────
-- Watches .git/HEAD only (branch switches, commits).
-- .git/index is deliberately excluded: it fires dozens of times per minute
-- under normal usage (git read-locks) and causes constant expensive refreshes.

local function setup_git_watchers()
	local git_dir = vim.trim(vim.fn.system("git rev-parse --git-dir 2>/dev/null"))
	if vim.v.shell_error ~= 0 or git_dir == "" then return end
	if git_dir:sub(1, 1) ~= "/" then git_dir = vim.fn.getcwd() .. "/" .. git_dir end

	local uv = vim.uv or vim.loop
	local w = uv.new_fs_event()
	if not w then return end
	pcall(function()
		w:start(git_dir .. "/HEAD", {}, function(err)
			if not err then
				vim.schedule(function()
					schedule_refresh(function() require("git_compare").invalidate_all() end)
				end)
			end
		end)
	end)
end

-- ── Public setup ─────────────────────────────────────────────────────────────

function M.setup()
	define_hl_groups()

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("GitCompareHLGroups", { clear = true }),
		callback = function() vim.schedule(define_hl_groups) end,
	})

	-- Register scrollbar handler (lazy: reads from cache at render time).
	pcall(function()
		require("scrollbar.handlers").register("git_compare", function(bufnr)
			local marks = {}
			if vim.bo[bufnr].buftype ~= "" then return marks end
			local filepath = vim.api.nvim_buf_get_name(bufnr)
			if filepath == "" then return marks end

			local gc = require("git_compare")
			local origin   = gc.get_origin_commit()
			local accepted = gc.get_accepted_commit()
			local total    = vim.api.nvim_buf_line_count(bufnr)
			-- For new-file (all-lines) case, cap mark density to avoid huge tables.
			local stride   = math.max(1, math.floor(total / 200))

			local function add_marks(commit, new_type, mod_type)
				if not commit then return end
				local status = gc.get_file_status(commit)
				if status.new[filepath] then
					for lnum = 0, total - 1, stride do
						table.insert(marks, { line = lnum, type = new_type, level = 1 })
					end
				else
					for _, hunk in ipairs(gc.get_line_hunks(commit, filepath)) do
						local t = hunk.kind == "new" and new_type or mod_type
						for _, lnum in ipairs(hunk.lines) do
							table.insert(marks, { line = lnum - 1, type = t, level = 1 })
						end
					end
				end
			end

			add_marks(origin,   "GitCompareOriginNew",   "GitCompareOriginModified")
			add_marks(accepted, "GitCompareAcceptNew",   "GitCompareAcceptModified")
			return marks
		end)
	end)

	setup_tree_hl()
	setup_git_watchers()

	local augroup = vim.api.nvim_create_augroup("GitCompareHL", { clear = true })

	-- New/updated buffer: warm then apply (non-blocking).
	vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost" }, {
		group = augroup,
		callback = function(ev)
			local bufnr = ev.buf
			local gc = require("git_compare")
			-- If cache is warm just apply immediately; otherwise warm first.
			if gc.get_origin_commit() then
				vim.schedule(function() apply_buf_hl(bufnr) end)
			else
				gc.warm_async(function() apply_buf_hl(bufnr) end)
			end
		end,
	})

	-- Save: partial invalidation for this file only.
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		callback = function(ev)
			local filepath = vim.api.nvim_buf_get_name(ev.buf)
			schedule_refresh(function() require("git_compare").invalidate_file(filepath) end)
		end,
	})

	-- External file change (e.g. Copilot writes directly to disk).
	vim.api.nvim_create_autocmd("FileChangedShellPost", {
		group = augroup,
		callback = function(ev)
			local filepath = vim.api.nvim_buf_get_name(ev.buf)
			schedule_refresh(function() require("git_compare").invalidate_file(filepath) end)
		end,
	})

	-- Focus return: full invalidation, throttled to once per 10 s.
	local _last_focus = 0
	vim.api.nvim_create_autocmd("FocusGained", {
		group = augroup,
		callback = function()
			local now = (vim.uv or vim.loop).hrtime() / 1e9
			if now - _last_focus < 10 then return end
			_last_focus = now
			schedule_refresh(function() require("git_compare").invalidate_all() end)
		end,
	})

	-- :Accept – snapshot working-tree as the accepted baseline.
	vim.api.nvim_create_user_command("Accept", function()
		vim.fn.system("git update-ref -d refs/nvim-accept/baseline 2>/dev/null")
		local stash_sha = vim.trim(vim.fn.system("git stash create 2>/dev/null"))
		local commit
		if vim.v.shell_error == 0 and stash_sha ~= "" then
			vim.fn.system("git update-ref refs/nvim-accept/baseline " .. stash_sha)
			commit = stash_sha
		else
			commit = vim.trim(vim.fn.system("git rev-parse HEAD 2>/dev/null"))
			if vim.v.shell_error ~= 0 or commit == "" then
				vim.notify("Accept: not in a git repository", vim.log.levels.ERROR); return
			end
			vim.fn.system("git update-ref refs/nvim-accept/baseline " .. commit)
		end
		local gc = require("git_compare")
		gc.set_accepted_commit(commit)
		schedule_refresh(function() gc.invalidate_all() end)
		vim.notify("Accepted baseline: " .. commit:sub(1, 8), vim.log.levels.INFO)
	end, { desc = "Snapshot current working-tree state as the accepted baseline" })

	vim.api.nvim_create_user_command("AcceptDiff", function()
		local accepted = require("git_compare").get_accepted_commit()
		if not accepted then
			vim.notify("AcceptDiff: no accepted commit set — run :Accept first", vim.log.levels.WARN); return
		end
		vim.cmd("CodeDiff " .. accepted)
	end, { desc = "Show diff between current state and accepted commit (CodeDiff)" })

	-- Pre-warm the cache in the background on startup so first BufEnter is instant.
	vim.schedule(function()
		require("git_compare").warm_async(function()
			refresh_visible_bufs()
		end)
	end)
end

return M
