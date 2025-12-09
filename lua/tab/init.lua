local M = {}
local ollama = require("tab.ollama")

local api = vim.api

local bnr = vim.fn.bufnr('%')
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
    local cursor_line = vim.fn.line('.')
    local cursor_col = vim.fn.col('.')
    local lines = api.nvim_buf_get_lines(0, cursor_line - 1, cursor_line, false)
    local autocomplete = ollama.make_request(vim.bo.filetype, lines[1])
    local opts = {
        end_line = 1,
        id = 1,
        virt_lines = text_to_virt_lines(autocomplete),
    }

    api.nvim_buf_set_extmark(bnr, ns_id, cursor_line - 1, cursor_col, opts)
end)

return M
