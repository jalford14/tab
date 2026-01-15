local M = {}

local function interp(s, tab)
  return (s:gsub('($%b{})', function(w) return tab[w:sub(3, -2)] or w end))
end

-- Escape JSON string for shell command
local function escape_json(str)
  return str:gsub('\\', '\\\\'):gsub("'", "'\\''")
end

function M.make_request_async(lang, snippet, callback)
    -- Escape the snippet for JSON
    local escaped_snippet = escape_json(snippet)
    local escaped_lang = escape_json(lang)
    
    -- Build the curl command
    local json_data = string.format('{"model": "tab", "prompt": "LANGAUGE: %s CODE: %s", "stream": false}', escaped_lang, escaped_snippet)
    
    -- Use jobstart for async execution (available in all Neovim versions)
    local stdout_data = {}
    local job_id = vim.fn.jobstart({"curl", "-s", "http://localhost:11434/api/generate", "-d", json_data}, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line and line ~= "" then
                        table.insert(stdout_data, line)
                    end
                end
            end
        end,
        on_exit = function(_, exit_code)
            if exit_code == 0 and #stdout_data > 0 then
                local raw_output = table.concat(stdout_data, "\n")
                local ok, parsed = pcall(vim.json.decode, raw_output)
                if ok and parsed and parsed.response then
                    callback(parsed.response)
                else
                    callback(nil)
                end
            else
                callback(nil)
            end
        end,
    })
    
    -- Return job_id so it can be cancelled if needed
    return job_id > 0 and job_id or nil
end

return M
