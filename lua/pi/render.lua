-- lua/pi/render.lua — 聊天渲染：markdown 文本写入 + 流式行内追加 + 高亮 + winbar header
local M = {}

-- 流式渲染状态：当前内容行是否已存在（true 时 stream 追加到行尾，false 时开新行）
local streaming_line = false

local NS = nil
local function ns()
  if not NS then NS = vim.api.nvim_create_namespace("pi-render") end
  return NS
end

local function define_highlights()
  if vim.g.pi_hl_defined then return end
  vim.api.nvim_set_hl(0, "PiHeaderUser", { fg = "#7aa2f7", bold = true })
  vim.api.nvim_set_hl(0, "PiHeaderAssistant", { fg = "#9ece6a", bold = true })
  vim.api.nvim_set_hl(0, "PiThinking", { fg = "#7f849c", italic = true })
  vim.api.nvim_set_hl(0, "PiTool", { fg = "#e0af68", bold = true })
  vim.api.nvim_set_hl(0, "PiToolDone", { fg = "#7f849c" })
  vim.g.pi_hl_defined = true
end

local function line_hl(line)
  if line:match("^── 用户") then return "PiHeaderUser" end
  if line:match("^── 助手") then return "PiHeaderAssistant" end
  if line:match("^%[thinking%]") then return "PiThinking" end
  if line:match("^%s*── thinking done") then return "PiThinking" end
  if line:match("^▸ ") then return "PiTool" end
  if line:match("^%s*── tool done") then return "PiToolDone" end
  return nil
end

local function highlight_lines(buf, start_idx, lines)
  for i, l in ipairs(lines) do
    local g = line_hl(l)
    if g then
      vim.api.nvim_buf_add_highlight(buf, ns(), g, start_idx + i - 1, 0, -1)
    end
  end
end

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
  vim.bo[buf].shiftwidth = 2  -- foldmethod=indent 按 shiftwidth 计算折叠级别，2 格缩进才成 fold
  define_highlights()
  if pcall(vim.treesitter.language.add, "markdown") then
    vim.bo[buf].filetype = "markdown"
  end
end

local active_fold_buf = nil

---记录用于 foldexpr/foldtext 的活跃 buffer（单实例 client，模块级即可）。
function M.set_fold_buf(buf)
  active_fold_buf = buf
end

function M.foldexpr_do()
  local lnum = vim.v.lnum
  if not active_fold_buf or not vim.api.nvim_buf_is_valid(active_fold_buf) then return 0 end
  local line = vim.api.nvim_buf_get_lines(active_fold_buf, lnum - 1, lnum, false)[1] or ""
  if line:sub(1, 2) == "  " then return 1 end
  return 0
end

function M.foldtext_do()
  if not active_fold_buf or not vim.api.nvim_buf_is_valid(active_fold_buf) then return "" end
  local s = vim.v.foldstart
  return vim.api.nvim_buf_get_lines(active_fold_buf, s - 1, s, false)[1] or ""
end

---窗口级选项。
---foldmethod=expr：2 格缩进行（thinking/工具输出）折叠为级 1。
---用 v:lua 表达式（Lua 函数值不被 vim.wo 接受；且不用 getline()，它解析当前 buffer，聊天窗口非当前时出错）。
function M.setup_window(win, buf)
  M.set_fold_buf(buf)
  vim.wo[win].foldmethod = "expr"
  vim.wo[win].foldlevel = 99
  vim.wo[win].foldcolumn = "1"
  vim.wo[win].foldexpr = "v:lua.require('pi.render').foldexpr_do()"
  vim.wo[win].foldtext = "v:lua.require('pi.render').foldtext_do()"
end

function M.reset(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "— pi session ready —" })
  streaming_line = false
end

---在 buffer 末尾追加若干行（插入到尾部空行之前），并按行前缀高亮。
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
  highlight_lines(buf, start_idx, lines)
end

function M.add_message(buf, role, time, content_blocks)
  M.begin_message(buf, role, time)
  M.add_content(buf, content_blocks)
end

---仅写消息头行（不写内容）。
function M.begin_message(buf, role, time)
  M.append(buf, M.header(role, time))
  streaming_line = false
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
  streaming_line = false
end

---text_start：新文本块，下一个 delta 从新行开始。
function M.begin_text(buf)
  streaming_line = false
end

function M.end_thinking(buf)
  M.append(buf, "  ── thinking done ──")
  streaming_line = false
end

---流式追加：无换行的 delta 接到当前内容行末尾（真实 pi 逐词推送，必须行内拼接）。
---流式追加：无换行的 delta 接到当前内容行末尾（真实 pi 逐词推送，必须行内拼接）。
---IND（可选）只在行首插入（新行起点 / 换行后续行），避免逐词追加时在行中间插入空格。
function M.stream(buf, text, ind)
  if text == "" then return end
  ind = ind or ""
  local count = vim.api.nvim_buf_line_count(buf)
  local idx = count - 1
  if idx >= 0 then
    local last = vim.api.nvim_buf_get_lines(buf, idx, idx + 1, false)[1]
    if last == "" then idx = idx - 1 end
  end
  local cur = (idx >= 0) and vim.api.nvim_buf_get_lines(buf, idx, idx + 1, false)[1] or ""
  local parts = vim.split(text, "\n", { plain = true })
  local first = parts[1]
  if streaming_line then
    vim.api.nvim_buf_set_lines(buf, idx, idx + 1, false, { cur .. first })
  else
    M.append(buf, ind .. first)
    streaming_line = true
  end
  for i = 2, #parts do
    if parts[i] ~= "" then
      M.append(buf, ind .. parts[i])
    end
  end
end

function M.start_tool(buf, event)
  local a = event.args or {}
  local summary = a.file_path or a.path or a.filename or a.command or ""
  M.append(buf, M.tool_line(event.toolName or "tool", summary))
  streaming_line = false
end

function M.update_tool(buf, event)
  if event.partialResult and event.partialResult ~= "" then
    M.append(buf, M.indent(event.partialResult, 2))
  end
end

function M.end_tool(buf, event)
  M.append(buf, "  ── tool done ──")
  streaming_line = false
end

---延迟折叠最近一个 [thinking] 块（foldmethod=indent：内容行缩进 2 格成 fold）。
function M.fold_last_thinking(buf, win, delay_ms)
  delay_ms = delay_ms or 3000
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    if not win or not vim.api.nvim_win_is_valid(win) then return end
    -- 从尾部向上找最后一个 [thinking] 头行
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local hdr = nil
    for i = #lines, 1, -1 do
      if lines[i]:match("^%[thinking%]") then hdr = i break end -- 1-based
    end
    if not hdr then return end
    local content_line = hdr + 1 -- 首行缩进内容 = fold 起点
    vim.api.nvim_win_call(win, function()
      vim.api.nvim_win_set_cursor(win, { content_line, 0 })
      vim.cmd("normal! zc")
    end)
  end, delay_ms)
end

function M.set_header(win, s)
  local model = s.model and (s.model.id or s.model) or "?"
  vim.wo[win].winbar = string.format("⏺ %s │ %s │ %s │ %s",
    model, s.thinking_level or "?", s.status or "?", s.session_name or "?")
end

return M
