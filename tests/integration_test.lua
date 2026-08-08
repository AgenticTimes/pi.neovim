local h = require("helpers")
local root = vim.fn.getcwd()

h.t("commands exist after plugin loads", function()
  require("pi").setup({})
  -- lazy.nvim 通过执行 plugin/ 目录下的入口文件注册命令；测试里显式加载
  dofile(root .. "/plugin/pi.lua")
  local ok1 = pcall(vim.cmd, "Pi")
  local ok2 = pcall(vim.cmd, "PiToggle")
  local ok3 = pcall(vim.cmd, "PiNewSession")
  local ok4 = pcall(vim.cmd, "PiCycleModel")
  local ok5 = pcall(vim.cmd, "PiCycleThinking")
  local ok6 = pcall(vim.cmd, "PiDiff")
  h.ok(ok1 and ok2 and ok3 and ok4 and ok5 and ok6, "all commands registered")
end)

h.t("full conversation via fake pi", function()
  require("pi").setup({})
  local client = require("pi.client")
  client.start({ cmd = { "node", root .. "/tests/fake_pi.mjs" }, cwd = root,
    on_event = function(ev) require("pi.events").dispatch(ev) end })
  h.wait(3000, function() return client.is_running() end, "fake pi up")

  local session = require("pi.session")
  local render = require("pi.render")
  local buf = h.new_buf()
  render.setup(buf)
  session.reset({})
  local done = false
  client.request("prompt", { message = "hi" }, function() done = true end)
  h.wait(3000, function() return done end, "prompt response")
  h.wait(3000, function()
    local s = session.get()
    if s.status == "streaming" and s.current_message and s.current_message.content then
      render.add_message(buf, "assistant", "00:00", s.current_message.content)
      return true
    end
    return false
  end, "message rendered")
  h.wait(3000, function() return session.get().status == "idle" end, "agent_end processed")
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local joined = table.concat(lines, "\n")
  h.ok(joined:match("hello from fake pi"), "assistant text rendered")
  client.stop()
end)
