-- lua/pi/runtime.lua — 会话运行时：pi 进程生命周期、初始状态拉取
-- 职责：启动/重启 pi RPC 进程，get_state/get_commands 初始化，退出错误回调。
-- UI（chat / terminal）通过 ensure_started(handlers) 接入，不直接操作 client。
local config = require("pi.config")
local client = require("pi.client")
local events = require("pi.events")
local session = require("pi.session")

local M = {}

local current_handlers = nil

---启动 pi 进程（单例）。HANDLERS：
---  on_ready()      — get_state 成功后（会话已就绪）
---  on_exit(code, signal) — 进程退出（含意外崩溃），由 UI 决定如何呈现
function M.ensure_started(handlers)
  current_handlers = handlers or current_handlers
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
      if current_handlers and current_handlers.on_exit then
        current_handlers.on_exit(code, signal)
      end
    end,
  })
  if not ok then return false end
  -- 会话就绪后拉初始状态；get_commands 依赖会话，紧随 get_state 之后
  client.request("get_state", {}, function(resp)
    if resp and resp.success then
      session.reset(resp.data)
      if current_handlers and current_handlers.on_ready then
        current_handlers.on_ready()
      end
      client.request("get_commands", {}, function(resp2)
        if resp2 and resp2.success then
          require("pi.completion").set_commands(resp2.data)
        end
      end)
    end
  end)
  return true
end

function M.is_running()
  return client.is_running()
end

return M
