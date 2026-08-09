-- lua/pi/ui.lua — 居中大 float：chat（winbar header）+ input 两个窗口
-- 职责：窗口/buffer 生命周期 + 事件→渲染翻译。进程生命周期见 pi.runtime。
local config = require("pi.config")
local events = require("pi.events")
local session = require("pi.session")

local M = {}
local wins = { chat = nil, input = nil }   -- window ids
local bufs = { chat = nil, input = nil }   -- buffer ids

function M._geometry(cols, lines, w_ratio, h_ratio)
  local width = math.floor(cols * w_ratio)
  local height = math.floor(lines * h_ratio)
  local input_h = math.max(6, math.floor(height * 0.2))
  local chat_h = height - input_h - 1
  local row = math.floor((lines - height) / 2)
  local col = math.floor((cols - width) / 2)
  local input_row = row + chat_h + 1
  return { width = width, height = height, input_h = input_h, chat_h = chat_h,
           row = row, col = col, input_row = input_row }
end

local function chat_buf_get()
  if bufs.chat and vim.api.nvim_buf_is_valid(bufs.chat) then return bufs.chat end
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(b, "pi://chat")
  bufs.chat = b
  require("pi.render").setup(b)
  require("pi.render").reset(b)
  return b
end

local function input_buf_get()
  if bufs.input and vim.api.nvim_buf_is_valid(bufs.input) then return bufs.input end
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(b, "pi://input")
  vim.bo[b].buftype = "nofile"
  vim.bo[b].bufhidden = "hide"
  bufs.input = b
  require("pi.input").set_buffer(b)
  require("pi.input").set_echo_fn(function(text)
    local cb = M.chat_buf()
    if cb then
      require("pi.render").add_message(cb, "user", os.date("%H:%M"), { { type = "text", text = text } })
    end
  end)
  require("pi.input").setup(b, function() M.close() end)
  require("pi.completion").setup(b)
  return b
end

local msg_streamed = {}  -- buf -> 当前消息是否已流式渲染（避免 message_end 重复）

local function render_event(ev)
  -- 事件 → 渲染翻译（ui 持有的 render hook）
  local buf = M.chat_buf()
  if not buf then return end
  local r = require("pi.render")
  if ev.type == "message_start" then
    if ev.message then
      -- 用户消息由 input.send 本地回显，这里跳过避免重复
      if ev.message.role ~= "user" then
        r.begin_message(buf, ev.message.role, os.date("%H:%M"))
      end
      msg_streamed[buf] = false
      -- message_start 若已带全文（如工具结果消息/fake pi），直接渲染
      if ev.message.content and #ev.message.content > 0 then
        r.add_content(buf, ev.message.content)
        msg_streamed[buf] = true
      end
    end
  elseif ev.type == "message_update" then
    local ae = ev.assistantMessageEvent
    if ae then
      if ae.type == "text_delta" then
        r.stream(buf, ae.delta)
        msg_streamed[buf] = true
      elseif ae.type == "text_start" then
        r.begin_text(buf)
      elseif ae.type == "text_end" then
        -- delta 已覆盖内容
      elseif ae.type == "thinking_start" then
        r.begin_thinking(buf)
        msg_streamed[buf] = true
      elseif ae.type == "thinking_delta" then
        r.stream(buf, ae.delta or "", "  ")
      elseif ae.type == "thinking_end" then
        r.end_thinking(buf)
        local delay = require("pi.config").get().thinking_fold_delay or 0
        if delay > 0 then
          local win = M.chat_win()
          if win then r.fold_last_thinking(buf, win, delay) end
        end
      -- toolcall delta：真实执行由 tool_execution_* 事件渲染，这里忽略
      end
    end
  elseif ev.type == "message_end" then
    -- 权威全文：若此前没有流式内容（例如未处理 delta 的消息），补渲染
    if not msg_streamed[buf] and ev.message and ev.message.content then
      r.add_content(buf, ev.message.content)
    end
    msg_streamed[buf] = false
  elseif ev.type == "tool_execution_start" then
    r.start_tool(buf, ev)
  elseif ev.type == "tool_execution_update" then
    r.update_tool(buf, ev)
  elseif ev.type == "tool_execution_end" then
    r.end_tool(buf, ev)
    require("pi.edits").reload_after(ev)
  end
  -- 状态类事件刷新 winbar header
  if ev.type ~= "message_start" and ev.type ~= "message_update" and ev.type ~= "message_end" then
    local win = M.chat_win()
    if win then r.set_header(win, session.get()) end
  end
end

local function start_runtime()
  -- 进程生命周期交给 runtime 模块；ui 只提供 on_ready / on_exit 呈现
  return require("pi.runtime").ensure_started({
    on_ready = function()
      local buf = M.chat_buf()
      if buf then
        require("pi.render").reset(buf)
        local win = M.chat_win()
        if win then require("pi.render").set_header(win, session.get()) end
      end
    end,
    on_exit = function(code, signal)
      if not M.is_open() then return end
      vim.schedule(function()
        local msg = "⚠ pi exited (code=" .. tostring(code) .. " signal=" .. tostring(signal) .. ")"
        local buf = M.chat_buf()
        if buf then
          require("pi.render").append(buf, msg)
          local tail = require("pi.client").stderr_tail()
          if #tail > 0 then
            require("pi.render").append(buf, table.concat(tail, "\n"))
          end
        end
        vim.notify(msg, vim.log.levels.ERROR)
      end)
    end,
  })
end

function M.open()
  if M.is_open() then M.focus_input() return end
  local cfg = config.get()
  local g = M._geometry(vim.o.columns, vim.o.lines, cfg.window.width, cfg.window.height)

  local chat = chat_buf_get()
  local input = input_buf_get()

  local chat_opts = {
    relative = "editor", row = g.row, col = g.col,
    width = g.width, height = g.chat_h, style = "minimal",
    border = cfg.window.border, noautocmd = true,
  }
  local input_opts = {
    relative = "editor", row = g.input_row, col = g.col,
    width = g.width, height = g.input_h, style = "minimal",
    border = cfg.window.border, noautocmd = true,
  }
  wins.chat = vim.api.nvim_open_win(chat, false, chat_opts)
  wins.input = vim.api.nvim_open_win(input, true, input_opts)
  require("pi.render").setup_window(wins.chat, chat)
  require("pi.render").set_header(wins.chat, session.get())
  -- 渲染钩子幂等注册（client 重启不丢）
  events.set_render_hook(render_event)
  require("pi.input").enter_insert(wins.input)
  start_runtime()
end

function M.close()
  if not M.is_open() then return end
  for _, w in pairs(wins) do
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
  wins.chat, wins.input = nil, nil
end

function M.is_open()
  return wins.chat ~= nil and vim.api.nvim_win_is_valid(wins.chat)
end

function M.chat_buf() return M.is_open() and chat_buf_get() or nil end
function M.input_buf() return M.is_open() and input_buf_get() or nil end
function M.chat_win() return M.is_open() and wins.chat or nil end
function M.input_win() return M.is_open() and wins.input or nil end

function M.focus_input()
  if M.is_open() then
    vim.api.nvim_set_current_win(wins.input)
    require("pi.input").enter_insert(wins.input)
  end
end

function M.toggle()
  if M.is_open() then M.close() else M.open() end
end

function M.on_resized()
  if not M.is_open() then return end
  local cfg = config.get()
  local g = M._geometry(vim.o.columns, vim.o.lines, cfg.window.width, cfg.window.height)
  vim.api.nvim_win_set_config(wins.chat, { relative = "editor", row = g.row, col = g.col,
    width = g.width, height = g.chat_h })
  vim.api.nvim_win_set_config(wins.input, { relative = "editor", row = g.input_row, col = g.col,
    width = g.width, height = g.input_h })
end

return M
