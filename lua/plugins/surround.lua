-- Plugin to surround visually selected text with braces, tags, or a character of your choosing
--
return {
    {
        'kylechui/nvim-surround',
        version = '^3.0.0', -- Use for stability; omit to use `main` branch for the latest features
        event = 'VeryLazy',
        config = function()
            require('nvim-surround').setup {}
        end,
    },
}
