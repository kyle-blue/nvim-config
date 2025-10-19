local is_win = function()
    return package.config.sub(1, 1) == '\\'
end

local get_path_sep = function()
    local sep = '/'
    if is_win() then
        sep = '//'
    end
    return sep
end

local get_current_file_dir = function()
    local file_path = debug.getinfo(2, 'S').source:sub(2)
    if is_win() then
        file_path = file_path:gsub('/', '\\')
    end
    return file_path:match('(.*' .. get_path_sep() .. ')')
end

-- Add nvim config to package.path so it can search here
package.path = package.path .. ';' .. get_current_file_dir() .. '?.lua'

require 'base_config'
require 'nvim-project-configuration'
require 'custom.remove_from_qf'

if vim.g.vscode or os.getenv("VSCODE_PID") then
    print("Loading vscode config...")
    require 'vscode_init'
    print("done!")
else
    print("Loading regular config...")
    require 'custom.run_file_on_save'
end

-- [[ Install `lazy.nvim` plugin manager ]]
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
    local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
    if vim.v.shell_error ~= 0 then
        error('Error cloning lazy.nvim:\n' .. out)
    end
end ---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
    -- Here is where all plugin configs live (./lua/plugins)
    { import = 'plugins' },
}, {
    ui = {
        -- Set lazy icon defaults in absence of nerd font
        icons = vim.g.have_nerd_font and {} or {
            cmd = '⌘',
            config = '🛠',
            event = '📅',
            ft = '📂',
            init = '⚙',
            keys = '🗝',
            plugin = '🔌',
            runtime = '💻',
            require = '🌙',
            source = '📄',
            start = '🚀',
            task = '📌',
            lazy = '💤 ',
        },
    },
})
