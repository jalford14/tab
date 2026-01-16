local M = {}
local ollama = require("tab.ollama")
local api = vim.api
local ns_id = api.nvim_create_namespace('tab')

local current_suggestions = {}
local debounce_timer = nil
local pending_requests = {}  -- Track pending requests to cancel them if needed

local function clean_suggestion_text(text)
    if text == nil then
        return ""
    end
    text = text:gsub("^```%w*%s*\n?", "")
    text = text:gsub("\n?%s*```%s*$", "")
    text = text:gsub("```", "")
    return text
end

local function text_to_virt_lines(text)
    if text == nil or text == "" then
        return nil
    end
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, {{line, "Comment"}})
    end
    return lines
end

local function clear_suggestion(bnr)
    -- Clear all extmarks for this buffer
    api.nvim_buf_clear_namespace(bnr, ns_id, 0, -1)
    current_suggestions[bnr] = nil
end

local function show_suggestion(bnr, line, col, suggestion_text, current_line_content)
    clear_suggestion(bnr)
    
    if not suggestion_text or suggestion_text == "" then
        return
    end
    
    -- Clean the full suggestion text
    local cleaned_text = clean_suggestion_text(suggestion_text)
    if cleaned_text == "" then
        return
    end
    
    -- Store the full suggestion text for tab completion
    current_suggestions[bnr] = {
        text = cleaned_text,  -- Store full text
        line = line,
    }
    
    -- Remove the already-typed portion from the beginning of the suggestion for display
    local display_text = cleaned_text
    if current_line_content and current_line_content ~= "" then
        -- Check if suggestion starts with what's already typed
        if cleaned_text:sub(1, #current_line_content) == current_line_content then
            -- Strip the already-typed portion
            display_text = cleaned_text:sub(#current_line_content + 1)
        end
    end
    
    -- If display_text is empty after stripping, don't show anything
    if display_text == "" then
        return
    end
    
    -- Show the suggestion: first line inline, rest as virtual lines below
    local suggestion_lines = vim.split(display_text, "\n")
    
    if #suggestion_lines > 0 then
        local first_line = suggestion_lines[1]
        local remaining_lines = {}
        for i = 2, #suggestion_lines do
            table.insert(remaining_lines, {{suggestion_lines[i], "Comment"}})
        end
        
        -- Show first line as inline virtual text
        local opts = {
            id = 1,
            virt_text = {{first_line, "Comment"}},
            hl_mode = "blend",
        }
        
        -- If there are more lines, add them as virtual lines below
        if #remaining_lines > 0 then
            opts.virt_lines = remaining_lines
        end
        
        local ok, err = pcall(api.nvim_buf_set_extmark, bnr, ns_id, line, 0, opts)
        if not ok then
            vim.notify("Error setting extmark: " .. tostring(err), vim.log.levels.ERROR)
        end
    end
end

local function request_autocomplete()
    local bnr = api.nvim_get_current_buf()
    local cursor_line = vim.fn.line('.') - 1  -- 0-indexed
    local cursor_col = vim.fn.col('.')
    local lines = api.nvim_buf_get_lines(bnr, cursor_line, cursor_line + 1, false)
    local line_content = lines[1] or ""
    local line_length = vim.fn.strlen(line_content)
    
    -- Clamp column to valid range (0-indexed, max is line_length)
    local col_0_indexed = math.min(cursor_col - 1, line_length)
    
    -- Store the position we're requesting for
    local request_line = cursor_line
    local request_col = cursor_col
    
    -- Cancel any pending request for this buffer
    if pending_requests[bnr] then
        vim.fn.jobstop(pending_requests[bnr])
        pending_requests[bnr] = nil
    end
    
    -- Make async request
    local job = ollama.make_request_async(vim.bo.filetype, line_content, function(autocomplete)
        -- Schedule the display update to ensure UI updates properly
        vim.schedule(function()
            -- Check if we're still in the same buffer and position
            local current_bnr = api.nvim_get_current_buf()
            if current_bnr == bnr then
                local current_line = vim.fn.line('.') - 1
                local current_col = vim.fn.col('.')
                -- Allow some movement tolerance
                if current_line == request_line and math.abs(current_col - request_col) <= 5 then
                    if autocomplete then
                        -- Get current line content to strip already-typed portion
                        local current_lines = api.nvim_buf_get_lines(bnr, request_line, request_line + 1, false)
                        local current_line_content = current_lines[1] or ""
                        show_suggestion(bnr, request_line, col_0_indexed, autocomplete, current_line_content)
                    end
                end
            end
            -- Clear the pending request
            pending_requests[bnr] = nil
        end)
    end)
    
    -- Store the job so we can cancel it if needed
    if job then
        pending_requests[bnr] = job
    end
end

local function debounced_autocomplete()
    -- Clear existing timer
    if debounce_timer then
        debounce_timer:stop()
        debounce_timer = nil
    end
    
    -- Clear current suggestion immediately when typing
    local bnr = api.nvim_get_current_buf()
    clear_suggestion(bnr)
    
    -- Set new timer for 200ms (0.2 seconds)
    debounce_timer = vim.defer_fn(function()
        request_autocomplete()
        debounce_timer = nil
    end, 200)
end

function M.setup()
  vim.notify("tab loaded!")
  
  -- Set up autocommand for automatic suggestions
  local augroup = api.nvim_create_augroup("TabAutocomplete", { clear = true })
  
  -- Trigger on text changes in insert mode (fires after text is inserted)
  api.nvim_create_autocmd("TextChangedI", {
    group = augroup,
    callback = function()
      debounced_autocomplete()
    end,
  })
  
  -- Clear suggestions when leaving insert mode
  api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    callback = function()
      local bnr = api.nvim_get_current_buf()
      clear_suggestion(bnr)
      if debounce_timer then
        debounce_timer:stop()
        debounce_timer = nil
      end
      -- Cancel any pending requests
      if pending_requests[bnr] then
        vim.fn.jobstop(pending_requests[bnr])
        pending_requests[bnr] = nil
      end
    end,
  })
  
  -- Shutdown server when leaving Neovim
  api.nvim_create_autocmd("VimLeave", {
    group = augroup,
    callback = function()
      ollama.shutdown_server()
    end,
  })
  
  -- Tab completion in insert mode
  vim.keymap.set("i", "<Tab>", function()
    local bnr = api.nvim_get_current_buf()
    local suggestion = current_suggestions[bnr]
    
    if suggestion then
      local full_text = suggestion.text
      
      if full_text ~= "" then
        -- Clear the suggestion first
        clear_suggestion(bnr)
        
        -- Replace the entire current line with the full suggestion
        -- Split suggestion into lines
        local suggestion_lines = vim.split(full_text, "\n")
        
        if #suggestion_lines > 0 then
          -- Use <C-o>cc to replace entire line and enter insert mode
          -- Then insert all lines of the suggestion
          local keys = "<C-o>cc"
          
          -- Insert all lines, with newlines between them
          for i, line in ipairs(suggestion_lines) do
            if i > 1 then
              keys = keys .. "<CR>"
            end
            keys = keys .. line:gsub("<", "<lt>")
          end
          
          -- Return the keys to execute
          return vim.api.nvim_replace_termcodes(keys, true, false, true)
        end
      end
    end
    
    -- Fall back to default Tab behavior
    return "<Tab>"
  end, { expr = true })
end

return M
