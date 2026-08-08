-- plugin/pi.lua — 插件入口（lazy.nvim 通过 cmd 触发 require）
local function cmd(name, fn)
  vim.api.nvim_create_user_command(name, fn, {})
end

cmd("Pi", function() require("pi").toggle() end)
cmd("PiToggle", function() require("pi").toggle() end)
cmd("PiNewSession", function() require("pi").new_session() end)
cmd("PiCycleModel", function() require("pi").cycle_model() end)
cmd("PiCycleThinking", function() require("pi").cycle_thinking_level() end)
cmd("PiDiff", function() require("pi.edits").diff() end)
