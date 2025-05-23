-- Better typescript lsp support (includes styled-components)

return {
    {
        'pmizio/typescript-tools.nvim',
        dependencies = { 'nvim-lua/plenary.nvim', 'neovim/nvim-lspconfig' },
        opts = {
            settings = {
                tsserver_plugins = {
                    '@styled/typescript-styled-plugin',
                },
            },
        },
    },
}
