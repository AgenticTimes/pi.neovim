-- lua/pi/input.lua — 输入区：发送/steer/abort/历史/补全入口
local config = require("pi.config")
local client = require("pi.client")
local context = require("pi.context")
local session = require("pi.session")

local M = {}
local history = {}      -- 最近在前
local history_index = 0

function M.get_text()
  local buf = M.current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return table.concat(lines, "\n")
end

function M.set_text(s)
  local buf = M.current_buf()
  local lines = (s == "") and {} or vim.split(s, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

local active_buf = nil
local echo_fn = nil

---ui 在打开时设置活动输入 buffer；解耦 input 对 ui 的依赖。
function M.set_buffer(buf)
  active_buf = buf
end

---ui 注入用户消息回显回调（text -> 渲染到聊天区）。
function M.set_echo_fn(fn)
  echo_fn = fn
end

function M.current_buf()
  if active_buf and vim.api.nvim_buf_is_valid(active_buf) then
    return active_buf
  end
  -- 测试或未打开时：用当前 buffer
  return vim.api.nvim_get_current_buf()
end

function M.send()
  local text = M.get_text()
  if text == "" then return end
  M.set_text("")
  if #history == 0 or history[#history] ~= text then
    table.insert(history, text)          -- 追加，最旧在前
    if #history > 100 then table.remove(history, 1) end
  end
  history_index = #history               -- 指向最新；M-p 回到上一条
  -- 用户消息回显（回调由 ui 注入，解耦 input 对 ui 的依赖）
  if echo_fn then
    echo_fn(text)
  end
  local message = context.expand(text)
  if not client.is_running() then
    vim.notify("pi not running; prompt not sent", vim.log.levels.WARN)
    return
  end
  local st = session.get().status
  if st == "idle" then
    client.request("prompt", { message = message, streamingBehavior = "steer" }, function() end)
  else
    client.request("follow_up", { message = message }, function() end)
  end
end

function M.steer()
  if not client.is_running() then return end
  if session.get().status == "idle" then return end
  local text = M.get_text()
  if text == "" then return end
  M.set_text("")
  client.request("steer", { message = text }, function() end)
end

function M.abort()
  if client.is_running() then
    client.notify("abort", {})
  end
end

function M.clear()
  M.set_text("")
  history_index = 0
end

function M.history(delta)
  if #history == 0 then return end
  history_index = math.max(0, math.min(#history, history_index + delta))
  if history_index == 0 then
    M.set_text("")
  else
    M.set_text(history[history_index])
  end
end

function M.enter_insert(win)
  -- 接收显式窗口参数（ui 传入），不反向 require ui
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
  vim.cmd("startinsert")
end

function M.setup(buf, close_fn)
  local keys = config.get().keys
  vim.keymap.set({ "i", "n" }, keys.send, function() M.send() end, { buffer = buf, desc = "pi: send" })
  vim.keymap.set({ "i", "n" }, keys.steer, function() M.steer() end, { buffer = buf, desc = "pi: steer" })
  vim.keymap.set({ "i", "n" }, keys.abort, function() M.abort() end, { buffer = buf, desc = "pi: abort" })
  vim.keymap.set({ "i", "n" }, keys.clear, function() M.clear() end, { buffer = buf, desc = "pi: clear input" })
  vim.keymap.set("i", keys.history_prev, function() M.history(-1) end, { buffer = buf, desc = "pi: history prev" })
  vim.keymap.set("i", keys.history_next, function() M.history(1) end, { buffer = buf, desc = "pi: history next" })
  if close_fn then
    vim.keymap.set("n", keys.close, close_fn, { buffer = buf, desc = "pi: close" })
  end
end

return M
