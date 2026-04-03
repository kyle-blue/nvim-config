-- nvim can override these with build in filetype plugins therefore 
-- we must also change these here (on load of buffer)
vim.api.nvim_create_autocmd("FileType", {
    pattern = "*",
    callback = function () 
        vim.opt_local.formatoptions:remove({"r", "o"})
    end,
})
