local M = {}
local ollama = require("tab.ollama")

local api = vim.api

local ns_id = api.nvim_create_namespace('tab')

local function text_to_virt_lines(text)
    if text ~= nil then
        text = text:gsub("^```%w*%s*\n?", "")
        text = text:gsub("\n?%s*```%s*$", "")
        text = text:gsub("```", "")
        local lines = {}
        for line in (text .. "\n"):gmatch("(.-)\n") do
            table.insert(lines, {{line, "Comment"}})
        end

        return lines
    else
        return nil
    end
end

function M.setup()
  vim.notify("tab loaded!")
end

vim.keymap.set("n", "<Leader>c", function()
    local bnr = api.nvim_get_current_buf()
    local cursor_line = vim.fn.line('.')
    local cursor_col = vim.fn.col('.')
    local lines = api.nvim_buf_get_lines(bnr, cursor_line - 1, cursor_line, false)
    local line_content = lines[1] or ""
    local line_length = vim.fn.strlen(line_content)
    
    -- Clamp column to valid range (0-indexed, max is line_length)
    local col_0_indexed = math.min(cursor_col - 1, line_length)
    
    local autocomplete = ollama.make_request(vim.bo.filetype, line_content)
    local opts = {
        end_line = 1,
        id = 1,
        virt_lines = text_to_virt_lines(autocomplete),
    }

    api.nvim_buf_set_extmark(bnr, ns_id, cursor_line - 1, col_0_indexed, opts)
end)

return M
