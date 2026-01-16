local M = {}

local server_starting = false
local server_start_attempts = 0
local server_pid = nil  -- Track the PID of the server we started

-- Escape JSON string for shell command
local function escape_json(str)
  return str:gsub('\\', '\\\\'):gsub("'", "'\\''")
end

local function start_ollama_server()
    if server_starting then
        return
    end
    
    server_starting = true
    server_start_attempts = server_start_attempts + 1
    
    vim.notify("Ollama server not running. Starting server...", vim.log.levels.INFO)
    
    -- Start ollama run tab in the background
    -- Use a marker file to track that we started it
    local marker_file = vim.fn.tempname() .. ".tab_ollama"
    local start_cmd = string.format(
        "nohup ollama run tab > /dev/null 2>&1 & echo $! > %s",
        marker_file
    )
    
    local job_id = vim.fn.jobstart({"sh", "-c", start_cmd}, {
        detach = true,
        on_exit = function(_, exit_code)
            server_starting = false
            if exit_code == 0 then
                -- Read the PID from the marker file
                vim.defer_fn(function()
                    local pid_file = io.open(marker_file, "r")
                    if pid_file then
                        local pid = pid_file:read("*n")
                        pid_file:close()
                        if pid then
                            server_pid = pid
                        end
                        os.remove(marker_file)
                    end
                    vim.notify("Ollama server started. Waiting for it to be ready...", vim.log.levels.INFO)
                    server_start_attempts = 0
                end, 100)  -- Small delay to let file be written
            else
                vim.notify("Failed to start Ollama server. Please start it manually with 'ollama run tab'", vim.log.levels.ERROR)
            end
        end,
    })
    
    if job_id <= 0 then
        server_starting = false
        vim.notify("Failed to start Ollama server process", vim.log.levels.ERROR)
    end
end

function M.shutdown_server()
    if server_pid then
        -- Kill the process we started
        vim.fn.jobstart({"kill", tostring(server_pid)}, { detach = true })
        server_pid = nil
        vim.notify("Ollama server shut down", vim.log.levels.INFO)
    else
        -- Fallback: try to kill any "ollama run tab" processes
        -- This is less precise but works if we lost track of the PID
        vim.fn.jobstart({"pkill", "-f", "ollama run tab"}, { detach = true })
    end
end

local function is_connection_error(stderr_data)
    if not stderr_data or #stderr_data == 0 then
        return false
    end
    
    local error_text = table.concat(stderr_data, "\n"):lower()
    return error_text:match("connection refused") ~= nil
           or error_text:match("couldn't connect") ~= nil
           or error_text:match("failed to connect") ~= nil
end

function M.make_request_async(lang, snippet, callback)
    -- Escape the snippet for JSON
    local escaped_snippet = escape_json(snippet)
    local escaped_lang = escape_json(lang)
    
    -- Build the curl command
    local json_data = string.format('{"model": "tab", "prompt": "LANGAUGE: %s CODE: %s", "stream": false}', escaped_lang, escaped_snippet)
    
    -- Use jobstart for async execution (available in all Neovim versions)
    local stdout_data = {}
    local stderr_data = {}
    local job_id = vim.fn.jobstart({"curl", "-s", "http://localhost:11434/api/generate", "-d", json_data}, {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line and line ~= "" then
                        table.insert(stdout_data, line)
                    end
                end
            end
        end,
        on_stderr = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line and line ~= "" then
                        table.insert(stderr_data, line)
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
                -- Check if it's a connection error
                if is_connection_error(stderr_data) and server_start_attempts < 3 then
                    -- Try to start the server
                    start_ollama_server()
                    -- Retry the request after a delay
                    vim.defer_fn(function()
                        M.make_request_async(lang, snippet, callback)
                    end, 3000)  -- Retry after 3 seconds
                else
                    callback(nil)
                end
            end
        end,
    })
    
    -- Return job_id so it can be cancelled if needed
    return job_id > 0 and job_id or nil
end

return M
