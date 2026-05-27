-- nvim can override these with build in filetype plugins therefore
-- we must also change these here (on load of buffer)
vim.api.nvim_create_autocmd("FileType", {
	pattern = "*",
	callback = function()
		vim.opt_local.formatoptions:remove({ "r", "o" })
	end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking (copying) text",
	group = vim.api.nvim_create_augroup("HighlightYankPost", { clear = true }),
	callback = function()
		vim.highlight.on_yank()
	end,
})

-- If a file changes on disk while we have unsaved edits, warn instead of
-- silently discarding in-buffer changes. Prevents autoread from reverting
-- work in progress (e.g. when an LSP or external tool rewrites the file).
vim.api.nvim_create_autocmd("FileChangedShell", {
	pattern = "*",
	callback = function()
		if vim.bo.modified then
			vim.v.fcs_choice = "warn"
		else
			vim.v.fcs_choice = "reload"
		end
	end,
})

-- Bootstrap git-compare highlighting after all plugins have loaded.
vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = function()
		vim.schedule(function()
			require("core.git_compare_hl").setup()
			require("git_compare_sidebar").setup()
		end)
	end,
})
