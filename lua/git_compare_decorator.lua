-- git_compare_decorator.lua
-- nvim-tree custom decorator that highlights file names in the tree based on
-- their git status relative to two baselines:
--
--   "origin"   – merge-base with the upstream branch (muted green / orange)
--   "accepted" – the manually pinned commit set by :Accept (vivid green / orange)
--
-- Register this during nvim-tree setup via renderer.decorators (see nvimtree.lua).

local Decorator = require("nvim-tree.api").Decorator

---@class GitCompareDecorator: nvim_tree.api.Decorator
local GitCompareDecorator = Decorator:extend()

-- Called once per tree render.
function GitCompareDecorator:new()
	self.enabled = true
	self.highlight_range = "all" -- full row background, not just the filename text
	self.icon_placement = "none"

	local gc = require("git_compare")
	self.git_root = gc.git_root()

	local origin = gc.get_origin_commit()
	local accepted = gc.get_accepted_commit()

	-- Pre-fetch status tables (cached after the first call per commit SHA).
	self.origin_status = gc.get_file_status(origin)
	self.accept_status = gc.get_file_status(accepted)
end

-- Return the appropriate highlight group for a node, or nil for no change.
---@param node nvim_tree.api.Node
---@return string? highlight_group
function GitCompareDecorator:highlight_group(node)
	local abs = node.absolute_path
	if not abs then
		return nil
	end

	-- Derive git-root-relative path from the absolute path.
	local rel = (self.git_root and abs:sub(#self.git_root + 2)) or abs

	-- Accepted baseline takes visual precedence (more intense colours).
	if self.accept_status.new[abs] or self.accept_status.new[rel] then
		return "GitCompareAcceptNew"
	elseif self.accept_status.modified[abs] or self.accept_status.modified[rel] then
		return "GitCompareAcceptModified"
	elseif self.origin_status.new[abs] or self.origin_status.new[rel] then
		return "GitCompareOriginNew"
	elseif self.origin_status.modified[abs] or self.origin_status.modified[rel] then
		return "GitCompareOriginModified"
	end

	return nil
end

return GitCompareDecorator
