-- Detects Angular workspaces so Angular tooling stays out of React/other projects
local M = {}

local cache = {}

local function has_angular_core(package_json)
	local ok, content = pcall(vim.fn.readblob, package_json)
	if not ok or not content then
		return false
	end
	local ok_json, json = pcall(vim.json.decode, content)
	if not ok_json or type(json) ~= "table" then
		return false
	end
	return (json.dependencies or {})["@angular/core"] ~= nil or (json.devDependencies or {})["@angular/core"] ~= nil
end

-- Returns the Angular workspace root for `path`, or nil when not inside one.
-- angular.json is authoritative; otherwise (e.g. Nx) the nearest package.json must depend on @angular/core.
function M.root(path)
	if not path or path == "" then
		return nil
	end
	local dir = vim.fs.dirname(vim.fs.normalize(path))
	if cache[dir] ~= nil then
		return cache[dir] or nil
	end

	local root = vim.fs.root(dir, "angular.json")
	if not root then
		local package_json = vim.fs.find("package.json", { path = dir, upward = true })[1]
		if package_json and has_angular_core(package_json) then
			root = vim.fs.dirname(package_json)
		end
	end

	cache[dir] = root or false
	return root
end

return M
