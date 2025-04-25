local run_workspace_files = function(event)
    local workspace_dir = vim.fn.getcwd()
    ---@type string
    local nvim_files = vim.fn.glob(workspace_dir .. '/.nvim/*')
    for file in nvim_files:gmatch '[^\n]+' do
        dofile(file)
        -- TODO: Potentially specify a base config schema to make common actions easy
    end
end

vim.api.nvim_create_autocmd('VimEnter', {
    callback = run_workspace_files,
    group = vim.api.nvim_create_augroup('kblue-workspace-exec', { clear = true }),
})
