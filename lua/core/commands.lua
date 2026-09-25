vim.api.nvim_create_user_command("Blame", function()
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		vim.notify("Blame: buffer has no file", vim.log.levels.WARN)
		return
	end
	local line = vim.api.nvim_win_get_cursor(0)[1]
	-- --contents - blames the buffer as it is now, so unsaved edits don't shift line numbers
	local contents = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") .. "\n"
	local result = vim.system({
		"git",
		"-C",
		vim.fs.dirname(file),
		"blame",
		"--porcelain",
		"-L",
		line .. "," .. line,
		"--contents",
		"-",
		"--",
		file,
	}, { stdin = contents, text = true }):wait()
	if result.code ~= 0 then
		vim.notify("Blame: " .. vim.trim(result.stderr), vim.log.levels.WARN)
		return
	end

	local sha = result.stdout:match("^(%x+)")
	local author = result.stdout:match("\nauthor ([^\n]*)")
	local time = tonumber(result.stdout:match("\nauthor%-time (%d+)"))
	local summary = result.stdout:match("\nsummary ([^\n]*)")
	if sha:match("^0+$") then
		vim.api.nvim_echo({ { "Not committed yet", "Comment" } }, false, {})
		return
	end
	vim.api.nvim_echo({
		{ sha:sub(1, 8), "Identifier" },
		{ " " .. author .. ", " .. os.date("%Y-%m-%d %H:%M", time), "Comment" },
		{ " · " .. summary },
	}, false, {})
end, { desc = "Show git blame for the current line" })

-- User commands must start uppercase; let `:blame` expand to `:Blame`
vim.keymap.set("ca", "blame", function()
	return (vim.fn.getcmdtype() == ":" and vim.fn.getcmdline() == "blame") and "Blame" or "blame"
end, { expr = true })
