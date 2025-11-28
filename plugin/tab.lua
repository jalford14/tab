local M = {}
local ollama = require("tab.ollama")

local api = vim.api

local bnr = vim.fn.bufnr('%')
local ns_id = api.nvim_create_namespace('demo')

local line_num = 0
local col_num = 0

local function text_to_virt_lines(text)
    if text ~= nil then
        text = text:gsub("`", "")
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
    local autocomplete = ollama.make_request("if(a > b) {")
    local opts = {
        end_line = 1,
        id = 1,
        virt_lines = text_to_virt_lines(autocomplete),
    }

    api.nvim_buf_set_extmark(bnr, ns_id, line_num, col_num, opts)
end)

return M
