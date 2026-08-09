-- lua/pi/terminal.lua — 原生 pi TUI 的 float 终端薄封装
-- 与 opencode 集成的模式一致：85%×85% 居中圆角 float 里跑 `pi`，可随时 toggle。
local M = {}
local win_id = nil
local buf_id = nil

local function geometry()
  local cfg = require("pi.config").get().window or { width = 0.85, height = 0.85, border = "rounded" }
  local w = math.floor(vim.o.columns * cfg.width)
  local h = math.floor(vim.o.lines * cfg.height)
  return {
    relative = "editor",
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
    width = w,
    height = h,
    style = "minimal",
    border = cfg.border or "rounded",
  }
end

---确保终端 buffer 存在。
local function ensure_buf()
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
    buf_id = vim.api.nvim_create_buf(false, true)
    vim.bo[buf_id].bufhidden = "hide"
  end
  return buf_id
end

---在后台 buffer 里启动 pi（无窗口），预热进程；打开时秒开。
---termopen 会把终端挂到「当前 buffer」上，所以必须用 nvim_buf_call 锁定到
---模块自己的 buffer，否则 pi 会跑到无关的当前 buffer 里，copy 也读不到内容。
function M.start_in_background()
  local b = ensure_buf()
  if not vim.b[b].pi_term_started then
    vim.api.nvim_buf_call(b, function()
      vim.fn.termopen("pi", { cwd = vim.fn.getcwd() })
    end)
    vim.b[b].pi_term_started = true
  end
end

---打开 float 终端并启动 pi（首次）。
function M.open()
  if M.is_open() then
    vim.api.nvim_set_current_win(win_id)
    vim.cmd("startinsert")
    return
  end
  local b = ensure_buf()
  win_id = vim.api.nvim_open_win(b, true, geometry())
  -- 首次在终端 buffer 里启动 pi（job 常驻，关窗不杀）
  if not vim.b[b].pi_term_started then
    vim.fn.termopen("pi", { cwd = vim.fn.getcwd() })
    vim.b[b].pi_term_started = true
  end
  vim.cmd("startinsert")
end

function M.close()
  if M.is_open() then
    vim.api.nvim_win_close(win_id, true)
  end
  win_id = nil
end

function M.is_open()
  return win_id ~= nil and vim.api.nvim_win_is_valid(win_id)
end

---返回终端 buffer id（未创建时为 nil）。供外部检查/测试使用。
function M.buf()
  return buf_id
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

function M.on_resized()
  if M.is_open() then
    vim.api.nvim_win_set_config(win_id, geometry())
  end
end

---复制终端 buffer 全部内容到剪贴板（含已被 TUI 交互刷掉的报警文本）。
function M.copy_terminal_text()
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
    vim.notify("pi 终端尚未启动", vim.log.levels.WARN)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  -- TUI 退出后终端 buffer 会用空行垫满整个屏幕高度，复制前剔除尾部空行
  while #lines > 0 and lines[#lines] == "" do
    lines[#lines] = nil
  end
  local text = table.concat(lines, "\n")
  if #text == 0 then
    vim.notify("pi 终端为空", vim.log.levels.INFO)
    return
  end
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  vim.notify(("已复制 pi 终端内容（%d 行，%d 字符）"):format(#lines, #text), vim.log.levels.INFO)
end

return M
