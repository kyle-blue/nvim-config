-- core/diagnostics.lua
-- Colour + underline the gutter line number on lines with errors/warnings.
-- The sign column alone is unreliable: git-compare places its ▌ sign at
-- priority 20, which outranks diagnostic signs (priority 10) in the
-- single-width sign column, so the number highlight is the indicator that
-- stays visible even when diff highlights are on.

local severity = vim.diagnostic.severity

-- Derive number-column groups from the active colorscheme's diagnostic colours.
local function define_numhl_groups()
	for _, name in ipairs({ "Error", "Warn" }) do
		local src = vim.api.nvim_get_hl(0, { name = "Diagnostic" .. name, link = false })
		vim.api.nvim_set_hl(0, "DiagnosticNumHl" .. name, {
			fg = src.fg,
			bold = true,
			underline = true,
		})
	end
end

define_numhl_groups()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("DiagnosticNumHl", { clear = true }),
	callback = define_numhl_groups,
})

vim.diagnostic.config({
	signs = {
		numhl = {
			[severity.ERROR] = "DiagnosticNumHlError",
			[severity.WARN] = "DiagnosticNumHlWarn",
		},
	},
})
