local function table_to_str(table, indent)
    if indent == nil then
        indent = 0
    end
    local indent_txt = (' '):rep(indent)
    local out = ''

    if type(table) ~= 'table' then
        return print 'Error: tried to print non-table type in print_table'
    end
    if table[1] ~= nil then
        for index, value in ipairs(table) do
            if type(value) == 'table' then
                out = out .. index .. '::' .. '\n'
                out = out .. table_to_str(value, indent + 2) .. '\n'
            else
                out = out .. indent_txt .. index .. ': ' .. value .. '\n'
            end
        end
    else
        for key, value in pairs(table) do
            if type(value) == 'table' then
                out = out .. key .. '::' .. '\n'
                out = out .. table_to_str(value, indent + 2) .. '\n'
            else
                out = out .. indent_txt .. key .. ': ' .. tostring(value) .. '\n'
            end
        end
    end
    return out
end

---@param table table table to print
local function print_table(table)
    print(table_to_str(table))
end

--- Creates a new empty scratch buffer and places it to the right of the current window
local function create_v_split_window()
    local new_buf = vim.api.nvim_create_buf(false, true)
    local new_win = vim.api.nvim_open_win(new_buf, false, { split = 'right' })

    return {
        bufnr = new_buf,
        winnr = new_win,
    }
end

---@param str string String to convert into table of strings, split by new lines.
---@return table strings_table table of strings returned
local function str_to_table_output(str)
    local full_output_table = {}
    local should_add_new_line = false
    for s in str:gmatch '([^\n]*)' do
        local is_new_line = s == ''
        if is_new_line and should_add_new_line == false then
            -- Only add consequetive newlines, since newlines are added by default on each table item
            should_add_new_line = true
        elseif is_new_line and should_add_new_line then
            table.insert(full_output_table, '')
        else
            table.insert(full_output_table, s)
            should_add_new_line = false
        end
    end
    return full_output_table
end

---@return string path Path to python executable. Will use venv or poetry env python3 executable if detected, else just returns python3
local function get_python_path()
    -- %1 is the capture, - is the same as * (but returns the minimum match instead)
    local success, poetry_sys_cmd = pcall(vim.system, { 'poetry', 'env', 'info', '-p' })
    local poetry_cmd_result = success and poetry_sys_cmd:wait()
    local poetry_env_location = ''
    if success then
        poetry_env_location = poetry_cmd_result.stdout:gsub('^%s*(.-)%s*$', '%1')
    end

    if poetry_env_location ~= '' and vim.fn.isdirectory(poetry_env_location) == 1 then
        return vim.fs.joinpath(poetry_env_location, '/bin', '/python3')
    else
        local bin_path = vim.fs.find('bin', { type = 'directory' })
        local python_path = #bin_path == 1 and vim.fs.find('python3', { path = bin_path[1] })
        local is_regular_venv = #bin_path == 1 and #python_path == 1
        if is_regular_venv then
            ---@diagnostic disable-next-line
            return python_path[1]
        end
    end
    return 'python3'
end

return {
    print_table = print_table,
    create_v_split_window = create_v_split_window,
    str_to_table_output = str_to_table_output,
    get_python_path = get_python_path,
    table_to_str = table_to_str,
}
