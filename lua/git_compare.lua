-- git_compare.lua
-- Utilities for comparing files/lines against a git baseline commit.
-- Two baselines are supported:
--   1. "origin" – the merge-base between HEAD and the upstream branch
--   2. "accepted" – a manually pinned commit saved in .git/nvim_accept_commit

local M = {}

local _cache = {
	origin_commit = nil,
	origin_commit_at = 0,
	git_root = nil,
	file_status = {}, -- [commit_sha] = { new = {abs: true}, modified = {abs: true} }
	file_list = {}, -- [commit_sha] = { new = {abs_path}, modified = {abs_path} } – files only, no dirs
	line_hunks = {}, -- ["sha:filepath"] = [{ lines = {lnums}, kind = "new"|"modified" }]
}

local CACHE_TTL = 30 -- seconds before re-running git commands

local function cached_git_root()
	if _cache.git_root then
		return _cache.git_root
	end
	local r = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null")
	if vim.v.shell_error ~= 0 then
		return nil
	end
	_cache.git_root = vim.trim(r)
	return _cache.git_root
end

-- Expose git root so the decorator can use it without an extra system call.
function M.git_root()
	return cached_git_root()
end

-- Returns the merge-base SHA between HEAD and the upstream remote branch.
function M.get_origin_commit()
	local now = os.time()
	if _cache.origin_commit and now - _cache.origin_commit_at < CACHE_TTL then
		return _cache.origin_commit
	end
	-- Try upstream tracking branch first, then fall back to common branch names.
	local attempts = {
		"git merge-base HEAD @{u} 2>/dev/null",
		"git merge-base HEAD origin/main 2>/dev/null",
		"git merge-base HEAD origin/master 2>/dev/null",
		"git merge-base HEAD origin/develop 2>/dev/null",
	}
	for _, cmd in ipairs(attempts) do
		local r = vim.fn.system(cmd)
		if vim.v.shell_error == 0 then
			local sha = vim.trim(r)
			if sha ~= "" then
				_cache.origin_commit = sha
				_cache.origin_commit_at = now
				return sha
			end
		end
	end
	return nil
end

-- Returns { new = {abs_path: true, rel_path: true}, modified = {...} }
-- for files AND directories changed between <commit> and the current working tree.
--
-- Directory colour rules (recursive):
--   • A directory is "new"      if it didn't exist at <commit> AND all changes beneath it
--     are additions (no modifications).
--   • A directory is "modified" if it existed at <commit>, OR if any modification lives
--     anywhere beneath it (even inside an otherwise-new sub-directory).
--   A changed file propagates its status up to every ancestor directory.
function M.get_file_status(commit)
	if not commit then
		return { new = {}, modified = {} }
	end
	if _cache.file_status[commit] then
		return _cache.file_status[commit]
	end

	local root = cached_git_root()

	-- ── Step 1: file-level diff ──────────────────────────────────────────────
	local diff_out = vim.fn.system("git diff --name-status " .. vim.fn.shellescape(commit) .. " 2>/dev/null")
	local status = { new = {}, modified = {} }
	local rel_new = {} -- relative paths only, for dir propagation
	local rel_modified = {}

	if vim.v.shell_error == 0 then
		for line in diff_out:gmatch("[^\n]+") do
			-- Renames: R100<tab>old_name<tab>new_name
			local s, name = line:match("^([AMCDR]%d*)\t[^\t]*\t(.+)$")
			if not s then
				s, name = line:match("^([AMCDR]%d*)\t(.+)$")
			end
			if s and name then
				local abs = root and (root .. "/" .. name) or name
				local first = s:sub(1, 1)
				if first == "A" then
					status.new[abs] = true
					status.new[name] = true
					rel_new[name] = true
				elseif first == "M" or first == "R" or first == "C" then
					status.modified[abs] = true
					status.modified[name] = true
					rel_modified[name] = true
				end
			end
		end
	end

	-- ── Step 1b: untracked files (never staged) ──────────────────────────────
	-- git diff doesn't include these, so we query them separately.
	if root then
		local untracked = vim.fn.system(
			"git ls-files --others --exclude-standard --full-name 2>/dev/null"
		)
		if vim.v.shell_error == 0 then
			for name in untracked:gmatch("[^\n]+") do
				local abs = root .. "/" .. name
				if not status.modified[abs] then
					status.new[abs] = true
					status.new[name] = true
					rel_new[name] = true
				end
			end
		end
	end

	-- ── Step 2: find directories that existed at <commit> ───────────────────
	local baseline_dirs = {}
	local ls_out = vim.fn.system(
		"git ls-tree -r --name-only " .. vim.fn.shellescape(commit) .. " 2>/dev/null"
	)
	if vim.v.shell_error == 0 then
		for filepath in ls_out:gmatch("[^\n]+") do
			local parts = {}
			for part in filepath:gmatch("[^/]+") do
				table.insert(parts, part)
			end
			-- All but the last component are directory paths.
			for i = 1, #parts - 1 do
				baseline_dirs[table.concat(parts, "/", 1, i)] = true
			end
		end
	end

	-- ── Step 3: propagate file statuses up to every ancestor directory ───────
	-- Rules:
	--   • "modified" file  → ancestor dir = "modified"  (unconditional)
	--   • "new"      file  → ancestor dir = "modified"  if the dir existed at baseline
	--                      → ancestor dir = "new"        if the dir is itself new
	--   Once a dir is marked "modified" it can never be downgraded to "new".
	local dir_status = {}

	local function propagate(rel_path, kind)
		local parts = {}
		for part in rel_path:gmatch("[^/]+") do
			table.insert(parts, part)
		end
		for i = 1, #parts - 1 do
			local dir = table.concat(parts, "/", 1, i)
			if dir_status[dir] ~= "modified" then -- already at worst state
				if kind == "modified" or baseline_dirs[dir] then
					-- existing dir touched, or any modification cascades upward
					dir_status[dir] = "modified"
				else
					-- new file inside a new dir → dir stays "new" for now
					dir_status[dir] = dir_status[dir] or "new"
				end
			end
		end
	end

	-- Process modified files first so existing-dir "modified" wins over "new"
	-- when we later process new files in the same ancestor dirs.
	for path in pairs(rel_modified) do
		propagate(path, "modified")
	end
	for path in pairs(rel_new) do
		propagate(path, "new")
	end

	-- ── Step 4: merge directory statuses into the shared maps ────────────────
	for dir, kind in pairs(dir_status) do
		local abs_dir = root and (root .. "/" .. dir) or dir
		if kind == "new" then
			status.new[dir] = true
			status.new[abs_dir] = true
		else
			status.modified[dir] = true
			status.modified[abs_dir] = true
		end
	end

	-- ── Step 5: build file-only list (no dirs) for the sidebar ───────────────
	local flist = { new = {}, modified = {} }
	for name in pairs(rel_new) do
		local abs = root and (root .. "/" .. name) or name
		flist.new[abs] = true
	end
	for name in pairs(rel_modified) do
		local abs = root and (root .. "/" .. name) or name
		flist.modified[abs] = true
	end

	_cache.file_status[commit] = status
	_cache.file_list[commit] = flist
	return status
end

-- Returns { new = {abs_path: true}, modified = {abs_path: true} } with only
-- files (no propagated directory entries).  Used by the sidebar panels.
function M.get_changed_file_list(commit)
	if not commit then
		return { new = {}, modified = {} }
	end
	if not _cache.file_list[commit] then
		M.get_file_status(commit) -- populates cache
	end
	return _cache.file_list[commit] or { new = {}, modified = {} }
end

-- Parse `git diff` output into a list of hunks.
-- Each hunk: { lines = {1-based line numbers in new file}, kind = "new"|"modified" }
-- kind = "modified" when the hunk has both additions and removals (context change).
-- kind = "new"      when the hunk has only additions (brand-new lines / new file).
local function parse_hunks(diff)
	local hunks = {}
	local cur = nil

	for line in (diff .. "\n"):gmatch("([^\n]*)\n") do
		-- @@ -old[,count] +new[,count] @@  (counts may be omitted when == 1)
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
				table.insert(cur.lines, cur.lnum)
				cur.has_added = true
				cur.lnum = cur.lnum + 1
			elseif ch == "-" and line:sub(1, 3) ~= "---" then
				cur.has_removed = true
				-- deletions don't advance the new-file line counter
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

-- Returns line-level hunks for <filepath> relative to <commit>.
function M.get_line_hunks(commit, filepath)
	if not commit or not filepath or filepath == "" then
		return {}
	end
	local key = commit .. ":" .. filepath
	if _cache.line_hunks[key] then
		return _cache.line_hunks[key]
	end

	local result = vim.fn.system(
		"git diff " .. vim.fn.shellescape(commit) .. " -- " .. vim.fn.shellescape(filepath) .. " 2>/dev/null"
	)
	local hunks = (vim.v.shell_error == 0) and parse_hunks(result) or {}
	_cache.line_hunks[key] = hunks
	return hunks
end

-- Accepted commit persistence ------------------------------------------------

local function accept_file()
	local gd = vim.trim(vim.fn.system("git rev-parse --git-dir 2>/dev/null"))
	if vim.v.shell_error ~= 0 or gd == "" then
		return nil
	end
	return gd .. "/nvim_accept_commit"
end

-- Read the currently accepted commit SHA (persisted in .git/nvim_accept_commit).
function M.get_accepted_commit()
	local f = accept_file()
	if not f then
		return nil
	end
	local ok, lines = pcall(vim.fn.readfile, f)
	if ok and lines and #lines > 0 then
		local sha = vim.trim(lines[1])
		return sha ~= "" and sha or nil
	end
	return nil
end

-- Persist a new accepted commit SHA.
function M.set_accepted_commit(commit)
	local f = accept_file()
	if not f then
		return
	end
	vim.fn.writefile({ commit }, f)
end

-- Cache invalidation ---------------------------------------------------------

-- Full invalidation (e.g. on FocusGained or after :Accept).
function M.invalidate_all()
	_cache.origin_commit = nil
	_cache.origin_commit_at = 0
	_cache.git_root = nil
	_cache.file_status = {}
	_cache.file_list = {}
	_cache.line_hunks = {}
end

-- Partial invalidation for a single file (e.g. on BufWritePost).
function M.invalidate_file(filepath)
	_cache.file_status = {} -- file sets are per-commit, easier to wipe all
	_cache.file_list = {}
	for key in pairs(_cache.line_hunks) do
		if filepath and key:find(filepath, 1, true) then
			_cache.line_hunks[key] = nil
		end
	end
end

return M
