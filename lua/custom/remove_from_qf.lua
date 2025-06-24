function Remove_qf_item()
    local curqfidx = vim.fn.line '.' -- Current line number
    local qfall = vim.fn.getqflist()

    -- Return if there are no items to remove
    if #qfall == 0 then
        return
    end

    -- Remove the item from the quickfix list (Lua tables are 1-indexed)
    table.remove(qfall, curqfidx)

    -- Update the quickfix list
    vim.fn.setqflist(qfall, 'r') -- 'r' replaces the current list

    -- Reopen quickfix window to refresh the list (optional, but good for visual feedback)
    vim.cmd 'copen'

    -- Try to maintain cursor position
    if #qfall > 0 then
        local new_idx = curqfidx
        -- If the deleted item was the last, move to the new last item
        if new_idx > #qfall then
            new_idx = #qfall
        end
        -- Ensure cursor is at least on the first item if the list isn't empty
        if new_idx == 0 and #qfall > 0 then
            new_idx = 1
        end
        vim.api.nvim_win_set_cursor(vim.fn.win_getid(), { new_idx, 0 })
    else
        -- If list is empty, close the quickfix window
        vim.cmd 'cclose'
    end
end

-- Autocommand to map 'dd' and 'd' in the quickfix window
vim.api.nvim_create_autocmd('FileType', {
    pattern = 'qf',
    callback = function(event)
        local opts = { buffer = event.buf, silent = true }
        vim.keymap.set('n', 'dd', '<Cmd>lua Remove_qf_item()<CR>', opts)
        vim.keymap.set('x', 'd', '<Cmd>lua Remove_qf_item_visual()<CR>', opts) -- For visual mode
    end,
})

-- For visual mode deletion (a bit more complex as you need to handle the range)
-- This is a simplified version; a more robust solution would iterate through the visual selection.
function Remove_qf_item_visual()
    local qfall = vim.fn.getqflist()
    local start_line = vim.fn.line 'v'
    local end_line = vim.fn.line '.'

    if start_line > end_line then
        start_line, end_line = end_line, start_line
    end

    -- Remove items in reverse order to avoid index issues
    for i = end_line, start_line, -1 do
        if i >= 1 and i <= #qfall then
            table.remove(qfall, i)
        end
    end

    vim.fn.setqflist(qfall, 'r')
    vim.cmd 'copen'
    -- Attempt to restore cursor position or move to a sensible place
    if #qfall > 0 then
        local new_cursor_line = math.min(start_line, #qfall)
        vim.api.nvim_win_set_cursor(vim.fn.win_getid(), { new_cursor_line, 0 })
    else
        vim.cmd 'cclose'
    end
end
