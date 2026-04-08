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
