-- Personal plugin that allows execution of current file on save, showing result in vsplit buffer
-- Currently supports python (detects poetry if exists), and nodejs

local util = require 'util'

local FileType = {
    Python = {},
    Js = {},
    Ts = {},
    Rust = {},
    Lua = {},
    Unknown = {},
}

local function get_file_type(file_path)
    local extension = string.match(file_path, '.-%.(%w+)$')

    if extension == 'ts' then
        return FileType.Ts
    elseif extension == 'js' then
        return FileType.Js
    elseif extension == 'lua' then
        return FileType.Lua
    elseif extension == 'rs' then
        return FileType.Rust
    elseif extension == 'py' then
        return FileType.Python
    end

    return FileType.Unknown
end

local run_file_on_save = function(_)
    local original_buf = vim.fn.getbufinfo(vim.api.nvim_get_current_buf())[1]
    local code_run_buf = util.create_v_split_window()

    local command = {}
    local file_path = vim.fs.normalize(original_buf.name)
    local file_type = get_file_type(file_path)
    if file_type == FileType.Python then
        local python_path = util.get_python_path()
        command = { python_path, file_path }
    elseif file_type == FileType.Js then
        command = { 'node', file_path }
    elseif file_type == FileType.Ts then
        command = { 'npx', 'tsx', file_path }
    elseif file_type == FileType.Lua then
        command = { 'luajit', file_path }
    elseif file_type == FileType.Rust then
        command = { 'cargo', 'run', file_path }
    else
        command = { 'echo', '"Unknown file type"' }
    end

    local cmd_info = vim.system(command):wait()
    local full_output = cmd_info.stdout or ''
    if cmd_info.stderr then
        full_output = full_output .. '\n\n--- STDERR ---\n\n' .. cmd_info.stderr
    end

    vim.api.nvim_buf_set_lines(code_run_buf.bufnr, 0, -1, false, util.str_to_table_output(full_output))
end

vim.api.nvim_create_user_command(
    'RunFileOnSave',
    run_file_on_save,
    { desc = 'Run the current file in vsplit window when saved.\nCurrently supports python and nodejs.' }
)

-- Create user command to attach and detach
-- Auto detach on buf close of either one (left or right) and clear autocmd
