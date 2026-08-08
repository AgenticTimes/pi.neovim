-- lua/pi/ui.lua — 居中大 float：chat（winbar header）+ input 两个窗口
local config = require("pi.config")
local client = require("pi.client")
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
  require("pi.input").setup(b)
  require("pi.completion").setup(b)
  return b
end

local function start_client_if_needed()
  if client.is_running() then return true end
  local cfg = config.get()
  local cmd = {}
  if type(cfg.executable) == "string" then
    cmd = { cfg.executable, "--mode", "rpc" }
  else
    cmd = vim.list_extend({}, cfg.executable)
  end
  local ok = client.start({
    cmd = cmd,
    cwd = vim.fn.getcwd(),
    on_event = function(ev) events.dispatch(ev) end,
    on_exit = function(code, signal)
      if not M.is_open() then return end
      vim.schedule(function()
        vim.notify("pi exited (code=" .. tostring(code) .. " signal=" .. tostring(signal) .. ")", vim.log.levels.ERROR)
      end)
    end,
  })
  if not ok then return false end
  -- 拉初始状态
  client.request("get_state", {}, function(resp)
    if resp and resp.success then
      session.reset(resp.data)
      local buf = M.chat_buf()
      if buf then
        require("pi.render").reset(buf)
        local win = M.chat_win()
        if win then require("pi.render").set_header(win, session.get()) end
      end
    end
  end)
  client.request("get_commands", {}, function(resp)
    if resp and resp.success then
      require("pi.completion").set_commands(resp.data)
    end
  end)
  return true
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
  require("pi.render").setup_window(wins.chat)
  require("pi.render").set_header(wins.chat, session.get())
  require("pi.input").enter_insert()
  start_client_if_needed()
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
    require("pi.input").enter_insert()
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
