return {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
        {
            '<leader>f',
            function()
                require('conform').format { async = true, lsp_format = 'fallback' }
            end,
            mode = '',
            desc = '[F]ormat buffer',
        },
    },
    opts = {
        formatters_by_ft = {
            lua = { 'stylua' },
            javascript = { 'prettier' },
            typescript = { 'prettier' },
            javascriptreact = { 'prettier' },
            typescriptreact = { 'prettier' },
            json = { 'prettier' },
            html = { 'prettier' },
            css = { 'prettier' },
            -- Go and Rust don't need external formatters here; Conform will 
            -- automatically fall back to gopls and rust_analyzer!
        },
        format_on_save = function(bufnr)
            if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
                return
            end
            return { timeout_ms = 500, lsp_format = 'fallback' }
        end,
    },
    init = function()
        vim.api.nvim_create_user_command('FormatDisable', function(args)
            if args.bang then
                vim.b.disable_autoformat = true
            else
                vim.g.disable_autoformat = true
            end
        end, { desc = 'Disable autoformat-on-save', bang = true })

        vim.api.nvim_create_user_command('FormatEnable', function()
            vim.b.disable_autoformat = false
            vim.g.disable_autoformat = false
        end, { desc = 'Re-enable autoformat-on-save' })
    end,
}
