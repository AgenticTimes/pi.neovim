-- lua/pi/render.lua — 聊天渲染：markdown 文本写入 + 缩进折叠块 + winbar header
local M = {}

function M.header(role, time, width)
  width = width or 60
  local role_label = role == "user" and "用户" or "助手"
  local prefix = string.format("── %s · %s ", role_label, time or "")
  local fill = string.rep("─", math.max(1, width - vim.fn.strwidth(prefix)))
  return prefix .. fill
end

function M.tool_line(name, summary)
  if summary and summary ~= "" then
    return "▸ " .. name .. "  " .. summary
  end
  return "▸ " .. name
end

function M.indent(text, n)
  if text == "" then return "" end
  local pad = string.rep(" ", n)
  return pad .. text:gsub("\n", "\n" .. pad)
end

function M.setup(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  if pcall(vim.treesitter.language.add, "markdown") then
    vim.bo[buf].filetype = "markdown"
  end
end

---窗口级选项（fold 相关在 Neovim 里是 window-local；foldlevelstart 是全局，改用 foldlevel）。
function M.setup_window(win)
  vim.wo[win].foldmethod = "indent"
  vim.wo[win].foldlevel = 99
  vim.wo[win].foldcolumn = "1"
end

function M.reset(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "— pi session ready —" })
end

function M.append(buf, text)
  if text == "" then return end
  local lines = vim.split(text, "\n", { plain = true })
  local count = vim.api.nvim_buf_line_count(buf)
  local start_idx = count
  -- nvim buffer 恒以空行结尾：插入到尾部空行之前，保证内容连续无空行
  if count >= 1 then
    local last = vim.api.nvim_buf_get_lines(buf, count - 1, count, false)[1]
    if last == "" then start_idx = count - 1 end
  end
  vim.api.nvim_buf_set_lines(buf, start_idx, start_idx, false, lines)
end

function M.add_message(buf, role, time, content_blocks)
  M.begin_message(buf, role, time)
  M.add_content(buf, content_blocks)
end

---仅写消息头行（不写内容）。
function M.begin_message(buf, role, time)
  M.append(buf, M.header(role, time))
end

---渲染 content blocks（不含头行）。
function M.add_content(buf, content_blocks)
  if not content_blocks then return end
  for _, block in ipairs(content_blocks) do
    if block.type == "text" and block.text then
      M.append(buf, block.text)
    elseif block.type == "thinking" then
      M.begin_thinking(buf)
      M.append(buf, M.indent(block.text or "", 2))
      M.end_thinking(buf)
    elseif block.type == "tool_call" then
      M.start_tool(buf, { toolName = block.name, args = block.args or {} })
    elseif block.type == "tool_result" then
      M.update_tool(buf, { partialResult = block.text or "" })
    end
  end
end

function M.begin_thinking(buf)
  M.append(buf, "[thinking]")
end

function M.end_thinking(buf)
  M.append(buf, "  ── thinking done ──")
end

function M.stream(buf, text)
  M.append(buf, text)
end

function M.start_tool(buf, event)
  local a = event.args or {}
  local summary = a.file_path or a.path or a.filename or a.command or ""
  M.append(buf, M.tool_line(event.toolName or "tool", summary))
end

function M.update_tool(buf, event)
  if event.partialResult and event.partialResult ~= "" then
    M.append(buf, M.indent(event.partialResult, 2))
  end
end

function M.end_tool(buf, event)
  M.append(buf, "  ── tool done ──")
end

function M.set_header(win, s)
  local model = s.model and (s.model.id or s.model) or "?"
  vim.wo[win].winbar = string.format("⏺ %s │ %s │ %s │ %s",
    model, s.thinking_level or "?", s.status or "?", s.session_name or "?")
end

return M
