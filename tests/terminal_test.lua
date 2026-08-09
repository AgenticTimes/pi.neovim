-- tests/terminal_test.lua — pi.terminal（原生 pi TUI float 终端）测试
local h = require("helpers")
local term = require("pi.terminal")

---重置模块状态，返回全新的 pi.terminal 实例（各测试互不污染）。
local function fresh_term()
  package.loaded["pi.terminal"] = nil
  return require("pi.terminal")
end

---临时接管 vim.notify 收集消息；无论测试成功/失败都会恢复。
---@param fn function 在通知被接管期间执行的函数
---@return string[] 收到的通知消息
local function with_notify_capture(fn)
  local old, msgs = vim.notify, {}
  vim.notify = function(msg) msgs[#msgs + 1] = tostring(msg) end
  local ok, err = pcall(fn)
  vim.notify = old
  if not ok then error(err, 0) end
  return msgs
end

---停止终端 buffer 里的 job，等它死透后注入确定内容（终端 buffer 平时不可写）。
---@param buf integer
---@param lines string[]
local function settle_term(buf, lines)
  local ch = vim.api.nvim_get_option_value("channel", { buf = buf })
  if ch and ch ~= 0 then pcall(vim.fn.jobstop, ch) end
  h.wait(3000, function()
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    return pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)
  end, "terminal buffer becomes writable")
end

h.t("toggle opens and closes a terminal float", function()
  term.toggle()
  h.ok(term.is_open(), "open after toggle")
  term.toggle()
  h.ok(not term.is_open(), "closed after toggle")
end)

h.t("reopen reuses the same terminal buffer", function()
  term.toggle()
  local buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
  term.toggle()
  term.toggle()
  h.eq(vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win()), buf, "same terminal buffer on reopen")
  term.toggle()
end)

h.t("open creates a centered 85% float", function()
  term.toggle()
  local cfg = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
  h.eq(cfg.width, math.floor(vim.o.columns * 0.85), "width is 85% of columns")
  h.eq(cfg.height, math.floor(vim.o.lines * 0.85), "height is 85% of lines")
  h.eq(cfg.row, math.floor((vim.o.lines - cfg.height) / 2), "row centered")
  h.eq(cfg.col, math.floor((vim.o.columns - cfg.width) / 2), "col centered")
  term.toggle()
end)

h.t("on_resized re-applies centered 85% geometry", function()
  term.toggle()
  local win = vim.api.nvim_get_current_win()
  local cols, lines = vim.o.columns, vim.o.lines
  vim.o.columns, vim.o.lines = cols + 20, lines + 20
  term.on_resized()
  local cfg = vim.api.nvim_win_get_config(win)
  local ew, eh = math.floor((cols + 20) * 0.85), math.floor((lines + 20) * 0.85)
  h.eq(cfg.width, ew, "width re-applied")
  h.eq(cfg.height, eh, "height re-applied")
  h.eq(cfg.row, math.floor((lines + 20 - eh) / 2), "row re-centered")
  h.eq(cfg.col, math.floor((cols + 20 - ew) / 2), "col re-centered")
  vim.o.columns, vim.o.lines = cols, lines
  term.on_resized()
  term.toggle()
end)

h.t("copy warns and leaves registers when terminal never started", function()
  local t = fresh_term()
  vim.fn.setreg("+", "sentinel")
  local msgs = with_notify_capture(function()
    t.copy_terminal_text()
  end)
  package.loaded["pi.terminal"] = term
  h.ok(#msgs == 1 and msgs[1] == "pi 终端尚未启动", "warned 'not started'")
  h.eq(vim.fn.getreg("+"), "sentinel", "register untouched")
end)

h.t("copy grabs terminal content and strips blank fill", function()
  local t = fresh_term()
  t.open()
  local buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
  settle_term(buf, { "pi 0.84.0", "warning: something", "", "", "" })
  vim.fn.setreg("+", "sentinel")
  vim.fn.setreg('"', "sentinel")
  t.copy_terminal_text()
  h.eq(vim.fn.getreg("+"), "pi 0.84.0\nwarning: something", "clipboard content without blank fill")
  h.eq(vim.fn.getreg('"'), "pi 0.84.0\nwarning: something", "unnamed register too")
  t.close()
end)

h.t("copy notifies when terminal buffer is blank", function()
  local t = fresh_term()
  t.open()
  local buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
  settle_term(buf, { "", "", "" })
  local msgs = with_notify_capture(function()
    t.copy_terminal_text()
  end)
  h.ok(#msgs == 1 and msgs[1] == "pi 终端为空", "notified 'empty'")
  t.close()
end)

h.t("start_in_background starts the job exactly once", function()
  local t = fresh_term()
  t.start_in_background()
  local b = t.buf()
  h.ok(b ~= nil and vim.api.nvim_buf_is_valid(b), "background buffer created")
  h.eq(vim.b[b].pi_term_started, true, "started flag set")
  local ch = vim.api.nvim_get_option_value("channel", { buf = b })
  h.ok(ch ~= nil and ch ~= 0, "terminal channel attached")
  t.start_in_background()
  h.eq(vim.api.nvim_get_option_value("channel", { buf = b }), ch, "no second job on repeat call")
  package.loaded["pi.terminal"] = term
end)
