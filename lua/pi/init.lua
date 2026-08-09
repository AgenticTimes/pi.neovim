-- lua/pi/init.lua — 入口：setup、公共 API
local M = { name = "pi.neovim" }

local config = require("pi.config")

function M.setup(opts)
  config.setup(opts)
  vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      require("pi.terminal").on_resized()
    end,
  })
  -- 后台预热：空闲时提前启动 pi（默认关闭，开启后首次打开秒开）
  local cfg = config.get()
  if cfg.warm_start then
    vim.defer_fn(function()
      require("pi.terminal").start_in_background()
    end, cfg.warm_start_delay or 2000)
  end
end

---toggle 原生 pi TUI 的 float 终端。
function M.toggle()
  require("pi.terminal").toggle()
end

return M
