-- plugin/pi.lua — 插件入口（lazy.nvim 通过 cmd 触发 require）
local function cmd(name, fn)
  vim.api.nvim_create_user_command(name, fn, {})
end

cmd("Pi", function() require("pi").toggle() end)          -- 原生 pi TUI float 终端
cmd("PiToggle", function() require("pi").toggle() end)
cmd("PiTermCopy", function() require("pi.terminal").copy_terminal_text() end)
