local M = {}

local command = "ollama serve"

local function interp(s, tab)
  return (s:gsub('($%b{})', function(w) return tab[w:sub(3, -2)] or w end))
end

function M.make_request(lang, snippet)
    local generate = interp("curl -s http://localhost:11434/api/generate -d '{\"model\": \"tab\", \"prompt\": \"LANGAUGE: ${lang} CODE: ${snippet}\", \"stream\": false}' 2>/dev/null", { lang = lang, snippet = snippet })
    local handle = io.popen(generate, "r")
    local output = nil
    if handle then
        local raw_output = handle:read("*a")
        handle:close()
        
        local ok, parsed = pcall(vim.json.decode, raw_output)
        if ok and parsed then
            output = parsed
        else
            vim.notify("Failed to parse JSON response: " .. (parsed or "unknown error"), vim.log.levels.ERROR)
            return nil
        end
    end

    return output.response or nil
end

return M
