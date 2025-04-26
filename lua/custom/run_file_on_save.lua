-- Personal plugin that allows execution of current file on save, showing result in vsplit buffer
-- Currently supports python (detects poetry if exists), and nodejs

local FileType = {
    Python = {},
    Js = {},
    Ts = {},
    Rust = {},
    Lua = {},
    Unknown = {},
}

local function print_table(table)
    if type(table) ~= 'table' then
        return print 'Error: tried to print non-table type in print_table'
    end
    if table[1] ~= nil then
        for index, value in ipairs(table) do
            print(index .. ': ' .. value)
        end
    else
        for key, value in pairs(table) do
            print(key .. ': ' .. value)
        end
    end
end

local function create_v_split_window()
    local new_buf = vim.api.nvim_create_buf(false, true)
    local new_win = vim.api.nvim_open_win(new_buf, false, { split = 'right' })

    return {
        bufnr = new_buf,
        winnr = new_win,
    }
end

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
    local code_run_buf = create_v_split_window()

    local command = {}
    local file_path = vim.fs.normalize(original_buf.name)
    local file_type = get_file_type(file_path)
    if file_type == FileType.Python then
        command = { 'python3', file_path }
        -- %1 is the capture, - is the same as * (but returns the minimum match instead)
        local poetry_env_location = vim.system({ 'poetry', 'env', 'info', '-p' }):wait().stdout:gsub('^%s*(.-)%s*$', '%1')
        if poetry_env_location ~= nil and vim.fn.isdirectory(poetry_env_location) == 1 then
            local python_path = vim.fs.joinpath(poetry_env_location, '/bin', '/python3')
            command = { python_path, file_path }
        else
            local bin_path = vim.fs.find('bin', { type = 'directory' })
            local python_path = #bin_path == 1 and vim.fs.find('python3', { path = bin_path[1] })
            local is_regular_venv = #bin_path == 1 and #python_path == 1
            if is_regular_venv then
                ---@diagnostic disable-next-line
                command = { python_path[1], file_path }
            end
        end
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
    local full_output_table = {}
    local should_add_new_line = false
    for str in full_output:gmatch '([^\n]*)' do
        local is_new_line = str == ''
        if is_new_line and should_add_new_line == false then
            -- Only add consequetive newlines, since newlines are added by default on each table item
            should_add_new_line = true
        elseif is_new_line and should_add_new_line then
            table.insert(full_output_table, '')
        else
            table.insert(full_output_table, str)
            should_add_new_line = false
        end
    end

    vim.api.nvim_buf_set_lines(code_run_buf.bufnr, 0, -1, false, full_output_table)
end

vim.api.nvim_create_user_command(
    'RunFileOnSave',
    run_file_on_save,
    { desc = 'Run the current file in vsplit window when saved.\nCurrently supports python and nodejs.' }
)

-- Create user command to attach and detach
-- Auto detach on buf close of either one (left or right) and clear autocmd
