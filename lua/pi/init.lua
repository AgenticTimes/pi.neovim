-- lua/pi/init.lua — 入口：setup、公共 API、命令注册
local M = { name = "pi.neovim" }

local config = require("pi.config")
local ui = require("pi.ui")
local events = require("pi.events")
local client = require("pi.client")

function M.setup(opts)
  config.setup(opts)
  vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      ui.on_resized()
      require("pi.terminal").on_resized()
    end,
  })
end

---默认动作：toggle 原生 pi TUI 的 float 终端（开箱即用）。
function M.toggle()
  require("pi.terminal").toggle()
end

---定制聊天 UI（上下文注入/PiEvent 等高级能力），需要时用 :PiChat。
function M.toggle_chat()
  ui.toggle()
end

function M.on(event_type, cb)
  return events.on(event_type, cb)
end

function M.new_session()
  if not client.is_running() then return end
  client.request("new_session", {}, function(resp)
    if resp and resp.success and not resp.data.cancelled then
      client.request("get_state", {}, function(r)
        if r and r.success then
          require("pi.session").reset(r.data)
          local buf = ui.chat_buf()
          if buf then
            require("pi.render").reset(buf)
          end
        end
      end)
    end
  end)
end

function M.cycle_model()
  if client.is_running() then client.request("cycle_model", {}, function() end) end
end

function M.cycle_thinking_level()
  if client.is_running() then client.request("cycle_thinking_level", {}, function() end) end
end

return M
