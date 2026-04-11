-- Define our shared formatting logic
local function notify_diagnostic(d)
	if not d then
		return
	end

	local severity_map = {
		[vim.diagnostic.severity.ERROR] = { icon = "󰅚 ", title = "Error", level = vim.log.levels.ERROR },
		[vim.diagnostic.severity.WARN] = { icon = "󰀪 ", title = "Warning", level = vim.log.levels.WARN },
		[vim.diagnostic.severity.INFO] = { icon = "󰋽 ", title = "Info", level = vim.log.levels.INFO },
		[vim.diagnostic.severity.HINT] = { icon = "󰌶 ", title = "Hint", level = vim.log.levels.INFO },
	}

	local sev = severity_map[d.severity] or severity_map[vim.diagnostic.severity.ERROR]
	local source = d.source and ("**Source:** `" .. d.source .. "`") or ""
	local code = d.code and ("**Code:** `" .. d.code .. "`") or ""

	local meta_parts = {}
	if source ~= "" then
		table.insert(meta_parts, source)
	end
	if code ~= "" then
		table.insert(meta_parts, code)
	end
	local meta_string = table.concat(meta_parts, "  |  ")

	local message = d.message or "No message content."
	local final_output = meta_string ~= "" and (meta_string .. "\n\n---\n\n" .. message) or message

	vim.notify(final_output, sev.level, { title = sev.icon .. " LSP " .. sev.title })
end

return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,
	opts = {
		picker = { enabled = true },
		notifier = { enabled = true },
		words = { enabled = true },
		input = {
			enabled = true,
			win = {
				keys = {
					-- Custom functionality to make sure alt backspace deletes a word in this menu also
					["<M-BS>"] = {
						function()
							local line = vim.api.nvim_get_current_line()
							local col = vim.api.nvim_win_get_cursor(0)[2] -- 0-indexed column

							if col == 0 then
								return
							end

							local before = line:sub(1, col)
							local after = line:sub(col + 1)

							-- 1. If we are currently on a separator, delete all contiguous separators
							local new_before = before:gsub("[%s%-_]+$", "")

							-- 2. If the line didn't change (we weren't on a separator),
							--    delete all contiguous non-separator characters (the "word")
							if new_before == before then
								new_before = before:gsub("[^%s%-_]+$", "")
							end

							-- 3. Update the line and move the cursor to the end of the new prefix
							vim.api.nvim_set_current_line(new_before .. after)
							vim.api.nvim_win_set_cursor(0, { 1, #new_before })
						end,
						mode = "i",
						desc = "Delete word backward (custom logic)",
					},
				},
			},
		},
	},
	keys = {
		{
			"<leader>sf",
			function()
				Snacks.picker.files()
			end,
			desc = "Search Files",
		},
		{
			"<leader>sg",
			function()
				Snacks.picker.grep()
			end,
			desc = "Search Grep",
		},

		-- Workspace Diagnostics Picker (<leader
		{
			"<leader>q",
			function()
				Snacks.picker.diagnostics({
					actions = {
						show_details = function(picker, item)
							-- We extract the raw Neovim diagnostic object (item.item)
							-- and pass it to our shared function
							if item and item.item then
								notify_diagnostic(item.item)
							else
								vim.notify("No diagnostic data found.", vim.log.levels.WARN)
							end
						end,
					},
					win = {
						input = {
							keys = { ["<C-d>"] = { "show_details", mode = { "i", "n" }, desc = "Show Details" } },
						},
						list = { keys = { ["<C-d>"] = { "show_details", mode = { "n" }, desc = "Show Details" } } },
					},
				})
			end,
			desc = "Workspace Diagnostics",
		},

		-- Current Line Diagnostics
		{
			"<leader>dl",
			function()
				local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
				local diagnostics = vim.diagnostic.get(0, { lnum = lnum })

				if #diagnostics == 0 then
					vim.notify("No diagnostics on this line.", vim.log.levels.INFO, { title = "Diagnostics" })
					return
				end

				-- Loop through the diagnostics and pass each one to our shared function
				for _, d in ipairs(diagnostics) do
					notify_diagnostic(d)
				end
			end,
			desc = "Show Diagnostics on Current Line",
		},
	},
}
