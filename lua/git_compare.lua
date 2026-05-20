-- git_compare.lua
-- Async git data layer for the two-baseline comparison highlighting system.
--
-- Design:
--   • All git I/O uses vim.system() (async, non-blocking).
--   • Request coalescing: if two callers ask for the same commit's status while
--     a fetch is in flight, only ONE git process runs; both callbacks fire when done.
--   • Sync getters (get_file_status etc.) return from cache instantly; callers
--     that need fresh data call M.warm_async(callback) first.
--   • Dir-stat index is pre-built during fetch → get_dir_stat() is O(1).

local M = {}

local _cache = {
	git_root         = nil,      -- session-constant: never cleared on invalidation
	origin_commit    = nil,
	origin_commit_at = 0,
	file_status      = {},  -- [commit] = {new={},modified={},deleted={}}
	file_list        = {},  -- [commit] = {new={},modified={},deleted={}} (files only)
	dir_index        = {},  -- [commit][abs_dir] = {added,deleted,changed}
	line_hunks       = {},  -- ["sha:filepath"] = [{lines,kind}]
	diff_stats       = {},  -- ["all:commit"] = {[abs]=a/r}, ["commit:stat:path"] = {a,r}
	_gen             = 0,
}

local CACHE_TTL = 30  -- seconds before re-fetching origin commit

-- ── Request coalescing ────────────────────────────────────────────────────────
-- _pending[key] = list of callbacks waiting for the result.
-- While a fetch is in flight the list exists; when done it is deleted.
local _pending = {}

local function coalesce(key, callback, start_fetch_fn)
	-- Cache hit: return immediately.
	if _cache.file_status[key] then
		callback(_cache.file_status[key])
		return
	end
	-- Already in flight: queue.
	if _pending[key] then
		table.insert(_pending[key], callback)
		return
	end
	-- Start a new fetch.
	_pending[key] = { callback }
	start_fetch_fn(function(result)
		local pending = _pending[key]
		_pending[key] = nil
		for _, cb in ipairs(pending or {}) do
			cb(result)
		end
	end)
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function git_root_sync()
	if _cache.git_root then return _cache.git_root end
	local r = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null")
	if vim.v.shell_error ~= 0 then return nil end
	_cache.git_root = vim.trim(r)
	return _cache.git_root
end

-- Non-blocking git command.  callback(stdout_or_nil) runs on the main thread.
local function git_async(args, callback)
	local root = git_root_sync()
	vim.system(args, { text = true, cwd = root or vim.fn.getcwd() }, function(obj)
		vim.schedule(function()
			callback(obj.code == 0 and obj.stdout or nil)
		end)
	end)
end

-- Parse raw output from `git diff --name-status` + `git ls-files --others`
-- + `git ls-tree -r --name-only` into status/flist/dir_index tables.
local function parse_file_status(root, diff_out, untracked_out, lstree_out)
	local status = { new = {}, modified = {}, deleted = {} }
	local rel_new, rel_modified, rel_deleted = {}, {}, {}

	-- diff --name-status
	for line in (diff_out or ""):gmatch("[^\n]+") do
		local s, name = line:match("^([AMCDR]%d*)\t[^\t]*\t(.+)$")
		if not s then s, name = line:match("^([AMCDR]%d*)\t(.+)$") end
		if s and name then
			local abs = root .. "/" .. name
			local first = s:sub(1, 1)
			if first == "A" then
				status.new[abs] = true; status.new[name] = true; rel_new[name] = true
			elseif first == "M" or first == "R" or first == "C" then
				status.modified[abs] = true; status.modified[name] = true; rel_modified[name] = true
			elseif first == "D" then
				status.deleted[abs] = true; status.deleted[name] = true; rel_deleted[name] = true
			end
		end
	end

	-- ls-files --others (untracked)
	for name in (untracked_out or ""):gmatch("[^\n]+") do
		local abs = root .. "/" .. name
		if not status.modified[abs] then
			status.new[abs] = true; status.new[name] = true; rel_new[name] = true
		end
	end

	-- ls-tree (directories that existed at baseline)
	local baseline_dirs = {}
	for filepath in (lstree_out or ""):gmatch("[^\n]+") do
		local parts = {}
		for p in filepath:gmatch("[^/]+") do table.insert(parts, p) end
		for i = 1, #parts - 1 do
			baseline_dirs[table.concat(parts, "/", 1, i)] = true
		end
	end

	-- Propagate file statuses up to ancestor directories.
	local dir_status = {}
	local function propagate(rel_path, kind)
		local parts = {}
		for p in rel_path:gmatch("[^/]+") do table.insert(parts, p) end
		for i = 1, #parts - 1 do
			local dir = table.concat(parts, "/", 1, i)
			if dir_status[dir] ~= "modified" then
				if kind == "modified" or baseline_dirs[dir] then
					dir_status[dir] = "modified"
				else
					dir_status[dir] = dir_status[dir] or "new"
				end
			end
		end
	end
	for path in pairs(rel_modified) do propagate(path, "modified") end
	for path in pairs(rel_deleted)  do propagate(path, "modified") end
	for path in pairs(rel_new)      do propagate(path, "new")      end

	for dir, kind in pairs(dir_status) do
		local abs_dir = root .. "/" .. dir
		if kind == "new" then
			status.new[dir] = true; status.new[abs_dir] = true
		else
			status.modified[dir] = true; status.modified[abs_dir] = true
		end
	end

	-- File-only list (no dir entries) used by sidebar.
	local flist = { new = {}, modified = {}, deleted = {} }
	for name in pairs(rel_new) do      flist.new[root .. "/" .. name] = true end
	for name in pairs(rel_modified) do flist.modified[root .. "/" .. name] = true end
	for name in pairs(rel_deleted) do  flist.deleted[root .. "/" .. name] = true end

	-- Pre-build dir-stat index: each directory key → {added, deleted, changed}.
	-- Scan once here so get_dir_stat() is O(1) instead of O(N·M).
	local dir_idx = {}
	local function accum(path, bucket)
		-- Walk every prefix of path (excluding the filename itself).
		local dir = path:match("^(.+)/[^/]+$")
		while dir and dir ~= root do
			if not dir_idx[dir] then
				dir_idx[dir] = { added = 0, deleted = 0, changed = 0 }
			end
			dir_idx[dir][bucket] = dir_idx[dir][bucket] + 1
			dir = dir:match("^(.+)/[^/]+$")
		end
	end
	for p in pairs(flist.new)      do accum(p, "added")   end
	for p in pairs(flist.modified) do accum(p, "changed")  end
	for p in pairs(flist.deleted)  do accum(p, "deleted")  end

	return status, flist, dir_idx
end

-- ── Async fetchers ────────────────────────────────────────────────────────────

-- Loads origin commit SHA asynchronously.
-- Tries @{u} first, then origin/main, origin/master, origin/develop in parallel.
local _origin_pending = nil  -- list of callbacks, or nil if not in flight
local function fetch_origin_async(callback)
	-- Cache hit
	if _cache.origin_commit and os.time() - _cache.origin_commit_at < CACHE_TTL then
		callback(_cache.origin_commit)
		return
	end
	-- Already in flight
	if _origin_pending then
		table.insert(_origin_pending, callback)
		return
	end
	_origin_pending = { callback }

	local function finish(sha)
		if sha and sha ~= "" then
			_cache.origin_commit = sha
			_cache.origin_commit_at = os.time()
		end
		local pending = _origin_pending
		_origin_pending = nil
		for _, cb in ipairs(pending or {}) do cb(sha ~= "" and sha or nil) end
	end

	-- Try @{u} first (most common, single round-trip).
	vim.system({ "git", "merge-base", "HEAD", "@{u}" }, { text = true }, function(obj)
		vim.schedule(function()
			if obj.code == 0 then
				local sha = vim.trim(obj.stdout)
				if sha ~= "" then finish(sha); return end
			end
			-- Try fallbacks in parallel; first success wins.
			local branches = { "origin/main", "origin/master", "origin/develop" }
			local done = 0
			local found = false
			for _, branch in ipairs(branches) do
				vim.system({ "git", "merge-base", "HEAD", branch }, { text = true }, function(obj2)
					vim.schedule(function()
						done = done + 1
						if not found and obj2.code == 0 then
							local sha = vim.trim(obj2.stdout)
							if sha ~= "" then
								found = true
								finish(sha)
								return
							end
						end
						if done == #branches and not found then
							finish("")
						end
					end)
				end)
			end
		end)
	end)
end

-- Loads file-status + file-list + dir-index for <commit> asynchronously.
-- The three git commands run in PARALLEL; result is cached on completion.
local function fetch_file_status_async(commit, callback)
	if _cache.file_status[commit] then
		callback(_cache.file_status[commit])
		return
	end
	local key = "fs:" .. commit
	if _pending[key] then
		table.insert(_pending[key], callback)
		return
	end
	_pending[key] = { callback }

	local root = git_root_sync()
	if not root then
		local empty = { new = {}, modified = {}, deleted = {} }
		_cache.file_status[commit] = empty
		_cache.file_list[commit]   = empty
		_cache.dir_index[commit]   = {}
		local pending = _pending[key]; _pending[key] = nil
		for _, cb in ipairs(pending or {}) do cb(empty) end
		return
	end

	-- Three git processes run in parallel.
	local results = {}
	local remaining = 3
	local function maybe_done()
		remaining = remaining - 1
		if remaining > 0 then return end
		local status, flist, dir_idx = parse_file_status(
			root, results.diff, results.untracked, results.lstree
		)
		_cache.file_status[commit] = status
		_cache.file_list[commit]   = flist
		_cache.dir_index[commit]   = dir_idx
		local pending = _pending[key]; _pending[key] = nil
		for _, cb in ipairs(pending or {}) do cb(status) end
	end

	vim.system(
		{ "git", "diff", "--name-status", commit },
		{ text = true, cwd = root },
		function(obj) vim.schedule(function() results.diff = obj.stdout; maybe_done() end) end
	)
	vim.system(
		{ "git", "ls-files", "--others", "--exclude-standard", "--full-name" },
		{ text = true, cwd = root },
		function(obj) vim.schedule(function() results.untracked = obj.stdout; maybe_done() end) end
	)
	vim.system(
		{ "git", "ls-tree", "-r", "--name-only", commit },
		{ text = true, cwd = root },
		function(obj) vim.schedule(function() results.lstree = obj.stdout; maybe_done() end) end
	)
end

-- Loads numstat for all modified files under <commit> asynchronously.
local function fetch_numstat_async(commit, callback)
	local key = "all:" .. commit
	if _cache.diff_stats[key] then callback(_cache.diff_stats[key]); return end
	local root = git_root_sync()
	if not root then callback({}); return end
	vim.system(
		{ "git", "diff", "--numstat", commit },
		{ text = true, cwd = root },
		function(obj)
			vim.schedule(function()
				local stats = {}
				for line in (obj.stdout or ""):gmatch("[^\n]+") do
					local a, r, name = line:match("^(%d+)\t(%d+)\t(.+)$")
					if a and r and name then
						stats[root .. "/" .. name] = { added = tonumber(a), removed = tonumber(r) }
					end
				end
				_cache.diff_stats[key] = stats
				callback(stats)
			end)
		end
	)
end

-- ── Public: warm the cache asynchronously ────────────────────────────────────
-- Ensures origin commit + both file-statuses are loaded, then calls callback().
-- If everything is already cached the callback fires in the same tick.
-- Pass force=true to re-fetch even if cache appears warm (used after invalidation).
function M.warm_async(callback, force)
	if force then
		_cache.origin_commit = nil
		_cache.origin_commit_at = 0
	end
	fetch_origin_async(function(origin)
		local accepted = M.get_accepted_commit()
		if not origin and not accepted then
			callback(); return
		end
		local remaining = 0
		if origin    then remaining = remaining + 1 end
		if accepted  then remaining = remaining + 1 end
		local function done()
			remaining = remaining - 1
			if remaining == 0 then callback() end
		end
		if origin   then fetch_file_status_async(origin,   done) end
		if accepted then fetch_file_status_async(accepted, done) end
	end)
end

-- ── Public: sync getters (return from cache; never block) ────────────────────

function M.git_root()
	return git_root_sync()
end

-- Returns cached origin commit SHA (may be nil if not yet loaded).
function M.get_origin_commit()
	return _cache.origin_commit
end

-- Returns cached file status for commit (may be empty if not yet loaded).
function M.get_file_status(commit)
	if not commit then return { new = {}, modified = {}, deleted = {} } end
	return _cache.file_status[commit] or { new = {}, modified = {}, deleted = {} }
end

-- Returns file-only list (no dir entries) for the sidebar.
function M.get_changed_file_list(commit)
	if not commit then return { new = {}, modified = {}, deleted = {} } end
	return _cache.file_list[commit] or { new = {}, modified = {}, deleted = {} }
end

-- Returns { added, removed } for a single file vs <commit>.  O(1) from cache.
-- For new/untracked files, removed=0 and added = cached numstat or line count.
function M.get_file_stat(commit, abs_path)
	if not commit or not abs_path or abs_path == "" then return { added = 0, removed = 0 } end
	local key = commit .. ":stat:" .. abs_path
	if _cache.diff_stats[key] then return _cache.diff_stats[key] end
	local status = M.get_file_status(commit)
	local stat
	if status.new[abs_path] then
		-- Estimate from numstat cache first; fall back to readfile only if needed.
		local all_key = "all:" .. commit
		local all = _cache.diff_stats[all_key]
		if all and all[abs_path] then
			stat = all[abs_path]
		else
			local ok, lines = pcall(vim.fn.readfile, abs_path)
			stat = { added = ok and #lines or 0, removed = 0 }
		end
	elseif status.modified[abs_path] then
		local all_key = "all:" .. commit
		local all = _cache.diff_stats[all_key]
		stat = (all and all[abs_path]) or { added = 0, removed = 0 }
	else
		stat = { added = 0, removed = 0 }
	end
	_cache.diff_stats[key] = stat
	return stat
end

-- Returns { added, deleted, changed } for a directory vs <commit>.  O(1) lookup.
function M.get_dir_stat(commit, abs_dir_path)
	if not commit or not abs_dir_path then return { added = 0, deleted = 0, changed = 0 } end
	local idx = _cache.dir_index[commit]
	if idx then
		return idx[abs_dir_path] or { added = 0, deleted = 0, changed = 0 }
	end
	-- Index not built yet; return zeros (will be correct after warm_async).
	return { added = 0, deleted = 0, changed = 0 }
end

-- ── Line hunks ────────────────────────────────────────────────────────────────

local function parse_hunks(diff)
	local hunks = {}
	local cur = nil
	for line in (diff .. "\n"):gmatch("([^\n]*)\n") do
		local ns = line:match("^@@ %-%d+,?%d* %+(%d+),?%d* @@")
		if ns then
			if cur and #cur.lines > 0 then
				cur.kind = (cur.has_added and cur.has_removed) and "modified" or "new"
				table.insert(hunks, cur)
			end
			cur = { lines = {}, has_added = false, has_removed = false, lnum = tonumber(ns) }
		elseif cur then
			local ch = line:sub(1, 1)
			if ch == "+" and line:sub(1, 3) ~= "+++" then
				table.insert(cur.lines, cur.lnum); cur.has_added = true; cur.lnum = cur.lnum + 1
			elseif ch == "-" and line:sub(1, 3) ~= "---" then
				cur.has_removed = true
			elseif ch == " " then
				cur.lnum = cur.lnum + 1
			end
		end
	end
	if cur and #cur.lines > 0 then
		cur.kind = (cur.has_added and cur.has_removed) and "modified" or "new"
		table.insert(hunks, cur)
	end
	return hunks
end

-- Returns line-level hunks for filepath vs commit.
-- Sync from cache; if not cached, spawns git diff async and returns {} for now.
-- The BufEnter / TextChanged paths always warm first, so this is usually a cache hit.
function M.get_line_hunks(commit, filepath)
	if not commit or not filepath or filepath == "" then return {} end
	local key = commit .. ":" .. filepath
	if _cache.line_hunks[key] then return _cache.line_hunks[key] end
	-- Not cached yet: fetch async and return empty (caller will re-apply on next event).
	vim.system(
		{ "git", "diff", commit, "--", filepath },
		{ text = true },
		function(obj)
			vim.schedule(function()
				_cache.line_hunks[key] = (obj.code == 0) and parse_hunks(obj.stdout or "") or {}
				-- Bump gen so the buffer-hash changes and highlights re-apply.
				_cache._gen = _cache._gen + 1
				-- Re-apply highlights for this buffer if it's currently loaded.
				for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
					if vim.api.nvim_buf_get_name(bufnr) == filepath and vim.api.nvim_buf_is_loaded(bufnr) then
						pcall(function() require("core.git_compare_hl").apply_buf(bufnr) end)
						break
					end
				end
			end)
		end
	)
	return {}
end

-- Warm line hunks for a specific file (called during buf warm pass).
function M.warm_line_hunks_async(commit, filepath, callback)
	if not commit or not filepath or filepath == "" then callback(); return end
	local key = commit .. ":" .. filepath
	if _cache.line_hunks[key] then callback(); return end
	vim.system(
		{ "git", "diff", commit, "--", filepath },
		{ text = true },
		function(obj)
			vim.schedule(function()
				_cache.line_hunks[key] = (obj.code == 0) and parse_hunks(obj.stdout or "") or {}
				callback()
			end)
		end
	)
end

-- ── Accepted commit persistence ───────────────────────────────────────────────

local function accept_file()
	local gd = vim.trim(vim.fn.system("git rev-parse --git-dir 2>/dev/null"))
	if vim.v.shell_error ~= 0 or gd == "" then return nil end
	return gd .. "/nvim_accept_commit"
end

function M.get_accepted_commit()
	local f = accept_file()
	if not f then return nil end
	local ok, lines = pcall(vim.fn.readfile, f)
	if ok and lines and #lines > 0 then
		local sha = vim.trim(lines[1])
		return sha ~= "" and sha or nil
	end
	return nil
end

function M.set_accepted_commit(commit)
	local f = accept_file()
	if f then vim.fn.writefile({ commit }, f) end
end

-- ── Cache invalidation ────────────────────────────────────────────────────────

function M.get_invalidation_gen()
	return _cache._gen
end

-- Full invalidation: clears everything except git_root (session-constant).
function M.invalidate_all()
	_cache._gen             = _cache._gen + 1
	_cache.origin_commit    = nil
	_cache.origin_commit_at = 0
	-- git_root intentionally kept: it never changes within a session.
	_cache.file_status  = {}
	_cache.file_list    = {}
	_cache.dir_index    = {}
	_cache.line_hunks   = {}
	_cache.diff_stats   = {}
	_pending = {}
	_origin_pending = nil
end

-- Partial invalidation for a single file (BufWritePost).
function M.invalidate_file(filepath)
	_cache._gen = _cache._gen + 1
	-- File sets and dir indexes must be rebuilt (file membership may have changed).
	_cache.file_status = {}
	_cache.file_list   = {}
	_cache.dir_index   = {}
	_cache.diff_stats  = {}
	-- Drop hunk cache only for the affected file.
	for key in pairs(_cache.line_hunks) do
		if filepath and key:find(filepath, 1, true) then
			_cache.line_hunks[key] = nil
		end
	end
	_pending = {}
end

return M
