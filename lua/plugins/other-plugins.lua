util = require 'util'
return {
    -- Theme
    {
        'folke/tokyonight.nvim',
        priority = 1000, -- Make sure to load this before all the other start plugins.
        config = function()
            ---@diagnostic disable-next-line: missing-fields
            require('tokyonight').setup {
                styles = {
                    comments = { italic = false }, -- Disable italics in comments
                },
                style = 'night',
                sidebars = 'dark',

                on_highlights = function(hg, colors)
                    hg.LineNr = {
                        fg = '#946d03',
                    }
                    hg.LineNrBelow = {
                        fg = '#946d03',
                    }
                    hg.LineNrAbove = {
                        fg = '#946d03',
                    }
                end,
            }

            vim.cmd.colorscheme 'tokyonight-night'
        end,
    },
    { 'folke/todo-comments.nvim', event = 'VimEnter', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } },
    {
        'tpope/vim-sleuth', -- Plugin which infers and sets tabwidth and other whitespace settings based of local project files
    },
}
