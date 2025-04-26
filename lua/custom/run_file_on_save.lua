-- Personal plugin that allows execution of current file on save, showing result in vsplit buffer
-- Currently supports python (detects poetry if exists), and nodejs

local POETRY_LOCATION = vim.fs.normalize '~/.local/bin/poetry'

local FileType = {
    Python = {},
    Js = {},
    Ts = {},
    Rust = {},
    Lua = {},
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
    print 'Creating v split window'
    local new_buf = vim.api.nvim_create_buf(false, true)
    local new_win = vim.api.nvim_open_win(new_buf, false, { split = 'right' })

    print 'Success'
    return {
        bufnr = new_buf,
        winnr = new_win,
    }
end

local run_file_on_save = function(cmd_info)
    local original_buf = vim.fn.getbufinfo(vim.api.nvim_get_current_buf())[1]
    local file_path = vim.fs.normalize(original_buf.name)
    local file_dir = vim.fs.dirname(file_path)
    -- Get file type
    -- If python, check for poetry installation,
    -- If js, run in node
    -- If ts run in tsx - use npx
    local file_type = FileType.Python

    local code_run_buf = create_v_split_window()

    local command = {}
    if file_type == FileType.Python then
        command = { 'python3', file_path }
        local poetry_env_location = vim.system({ POETRY_LOCATION, 'env', 'info', '-p' }):wait().stdout
        if poetry_env_location ~= nil and vim.fn.isdirectory(poetry_env_location) == 1 then
            command = { 'source', vim.fs.joinpath(poetry_env_location, '/bin', '/activate'), '&&', 'python3', file_path }
        else
            local bin_path = vim.fs.find('bin', { type = 'directory' })
            local activate_path = #bin_path == 1 and vim.fs.find('activate', { path = bin_path[1] })
            local is_regular_venv = #bin_path == 1 and #activate_path == 1
            if is_regular_venv then
                ---@diagnostic disable-next-line
                command = { 'source', vim.fs.joinpath(activate_path[1], '/bin', '/activate'), '&&', 'python3', file_path }
            end
        end
    elseif file_type == FileType.Js then
    end

    vim.api.nvim_buf_set_lines(code_run_buf.bufnr, 0, -1, false, {})
    vim.fn.jobstart(command, {
        on_stdout = function(_, data)
            vim.api.nvim_buf_set_lines(code_run_buf.bufnr, -1, -1, false, data)
        end,
        on_stderr = function(_, data)
            vim.api.nvim_buf_set_lines(code_run_buf.bufnr, -1, -1, false, data)
        end,
    })
end

vim.api.nvim_create_user_command(
    'RunFileOnSave',
    run_file_on_save,
    { desc = 'Run the current file in vsplit window when saved.\nCurrently supports python and nodejs.' }
)

-- Create user command to attach and detach
-- Auto detach on buf close of either one (left or right) and clear autocmd
