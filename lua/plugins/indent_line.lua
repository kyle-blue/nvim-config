-- Plugin to add indentation guides (vertical lines)

if vim.g.vscode then
    return {}
end

return {
    {
        'lukas-reineke/indent-blankline.nvim',
        main = 'ibl',
        opts = {},
    },
}
