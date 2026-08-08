-- lua/pi/events.lua — 事件分发：session 更新 + User PiEvent autocmd + 回调注册
local session = require("pi.session")

local M = {}
local handlers = {}  -- type -> { [fn] = true }

function M.on(event_type, cb)
  handlers[event_type] = handlers[event_type] or {}
  handlers[event_type][cb] = true
  return function()
    if handlers[event_type] then
      handlers[event_type][cb] = nil
    end
  end
end

function M.emit(event)
  -- 1) 注册的回调
  for type, set in pairs(handlers) do
    if type == "*" or type == event.type then
      for cb in pairs(set) do
        pcall(cb, event)
      end
    end
  end
  -- 2) User autocmd：vim.g.pi_event 是标准传值方式
  vim.g.pi_event = event
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "PiEvent" })
end

function M.dispatch(event)
  session.apply_event(event)
  M.emit(event)
end

return M
