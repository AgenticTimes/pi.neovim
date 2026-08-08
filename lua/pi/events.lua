-- lua/pi/events.lua — 事件分发：session 更新 + User PiEvent autocmd + 回调注册
local session = require("pi.session")

local M = {}
local handlers = {}  -- type -> { [fn] = true }
local render_hook = nil

---注册渲染钩子：每次事件在 session 更新后被调用（ui 持有，client 重启不丢）。
function M.set_render_hook(fn)
  render_hook = fn
end

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
  if render_hook then
    pcall(render_hook, event)
  end
  M.emit(event)
end

return M
