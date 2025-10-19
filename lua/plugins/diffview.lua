-- Plugin to show git diff on DiffviewOpen command
if vim.g.vscode then
    return {}
end

return {
    {
        'sindrets/diffview.nvim',
    },
}
