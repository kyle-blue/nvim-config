return {
	{
		"petertriho/nvim-scrollbar",
		config = function()
			local colors = require("tokyonight.colors").setup()

			require("scrollbar").setup({
				handle = {
					color = colors.bg_highlight,
				},
				-- Disable cursor mark: fires throttled_render on every CursorMoved
				handlers = {
					cursor     = false,
					diagnostic = true,
					gitsigns   = false,
					handle     = true,
				},
				-- Remove WinScrolled from render events; replaced by our 500ms debounce below
				autocmd = {
					render = {
						"BufWinEnter",
						"TabEnter",
						"TermEnter",
						"WinEnter",
						"CmdwinLeave",
						"TextChanged",
						"VimResized",
						-- WinScrolled handled below with 500ms debounce
					},
				},
				marks = {
					Search = { color = colors.orange },
					Error = { color = colors.error },
					Warn = { color = colors.warning },
					Info = { color = colors.info },
					Hint = { color = colors.hint },
					Misc = { color = colors.purple },
					-- git_compare tier 1 (origin): dimmer green / amber
					GitCompareOriginNew      = { text = "▌", color = "#00cc66", priority = 8 },
					GitCompareOriginModified = { text = "▌", color = "#cc6600", priority = 8 },
					-- git_compare tier 2 (accept): brighter — same as gutter bar signs
					GitCompareAcceptNew      = { text = "▌", color = "#00ffaa", priority = 9 },
					GitCompareAcceptModified = { text = "▌", color = "#ffaa00", priority = 9 },
				},
			})

			-- Debounced WinScrolled: render scrollbar 500ms after the last scroll event.
			-- Capturing the window at callback time so the timer closure can't use vim.v.event.
			local _scroll_timer = vim.uv.new_timer()
			local _scroll_win   = nil
			vim.api.nvim_create_autocmd("WinScrolled", {
				group = vim.api.nvim_create_augroup("ScrollbarDebounced", { clear = true }),
				callback = function()
					_scroll_win = vim.api.nvim_get_current_win()
					_scroll_timer:stop()
					_scroll_timer:start(500, 0, vim.schedule_wrap(function()
						local win = _scroll_win
						if win and vim.api.nvim_win_is_valid(win) then
							vim.api.nvim_win_call(win, function()
								require("scrollbar.handlers").show()
								require("scrollbar").render()
							end)
						end
					end))
				end,
			})
		end,
	},
}
