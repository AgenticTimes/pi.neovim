-- plugin/pi.lua — 插件入口（lazy.nvim 通过 cmd 触发 require）
local function cmd(name, fn)
  vim.api.nvim_create_user_command(name, fn, {})
end

cmd("Pi", function() require("pi").toggle() end)           -- 原生 pi TUI float 终端
cmd("PiToggle", function() require("pi").toggle() end)
cmd("PiChat", function() require("pi").toggle_chat() end)   -- 定制聊天 UI（上下文注入等）
cmd("PiNewSession", function() require("pi").new_session() end)
cmd("PiCycleModel", function() require("pi").cycle_model() end)
cmd("PiCycleThinking", function() require("pi").cycle_thinking_level() end)
cmd("PiDiff", function() require("pi.edits").diff() end)
cmd("PiTermCopy", function() require("pi.terminal").copy_terminal_text() end)
