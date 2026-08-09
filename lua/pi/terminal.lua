-- lua/pi/terminal.lua — 原生 pi TUI 的 float 终端薄封装
-- 与 opencode 集成的模式一致：85%×85% 居中圆角 float 里跑 `pi`，可随时 toggle。
local M = {}
local win_id = nil
local buf_id = nil

local function geometry()
  local w = math.floor(vim.o.columns * 0.85)
  local h = math.floor(vim.o.lines * 0.85)
  return {
    relative = "editor",
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
    width = w,
    height = h,
    style = "minimal",
    border = "rounded",
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
function M.start_in_background()
  local b = ensure_buf()
  if not vim.b[b].pi_term_started then
    vim.fn.termopen("pi", { cwd = vim.fn.getcwd() })
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

return M
