local h = require("helpers")
local render = require("pi.render")

h.t("header line has role, time and fill", function()
  local s = render.header("assistant", "14:32", 40)
  h.ok(s:match("^── 助手 · 14:32"), "prefix: " .. s)
  h.eq(vim.fn.strwidth(s), 40, "display width fills to 40")
end)

h.t("tool line shows name and summary", function()
  h.eq(render.tool_line("read", "src/app.ts"), "▸ read  src/app.ts")
  h.eq(render.tool_line("bash", nil), "▸ bash")
end)

h.t("indent prefixes every line", function()
  h.eq(render.indent("a\nb\nc", 2), "  a\n  b\n  c")
  h.eq(render.indent("", 2), "")
end)

h.t("buffer ops append and reset", function()
  local buf = h.new_buf()
  render.setup(buf)
  render.append(buf, "line1\nline2")
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  h.eq(lines[1], "line1")
  h.eq(lines[2], "line2")
  render.reset(buf)
  h.eq(#vim.api.nvim_buf_get_lines(buf, 0, -1, false), 1)
end)

h.t("setup_window applies window-local fold options", function()
  local buf = h.new_buf()
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", row = 0, col = 0, width = 80, height = 5, style = "minimal",
  })
  render.setup(buf)
  render.setup_window(win)
  h.eq(vim.wo[win].foldmethod, "indent")
  h.eq(vim.wo[win].foldcolumn, "1")
  vim.api.nvim_win_close(win, true)
end)

h.t("start/update/end tool produces indented foldable block", function()
  local buf = h.new_buf()
  render.setup(buf)
  render.start_tool(buf, { toolName = "write", args = { file_path = "a.txt" } })
  render.update_tool(buf, { toolCallId = "t1", partialResult = "ok" })
  render.end_tool(buf, { toolCallId = "t1" })
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  h.eq(lines[1], "▸ write  a.txt")
  h.ok(lines[2]:match("^  ok$"), "tool output indented: " .. tostring(lines[2]))
end)

h.t("stream concatenates deltas onto one line", function()
  local buf = h.new_buf()
  render.setup(buf)
  render.begin_message(buf, "assistant", "00:00")
  render.begin_text(buf)
  render.stream(buf, "Hello ")
  render.stream(buf, "world")
  render.stream(buf, " foo")
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- 内容应拼在同一个新行：Hello world foo
  local content_line
  for _, l in ipairs(lines) do
    if l == "Hello world foo" then content_line = l end
  end
  h.ok(content_line ~= nil, "deltas concatenated on one line; got: " .. vim.inspect(lines))
end)

h.t("stream indents only at line start (thinking deltas)", function()
  local buf = h.new_buf()
  render.setup(buf)
  render.begin_message(buf, "assistant", "00:00")
  render.begin_thinking(buf)
  render.stream(buf, "first", "  ")
  render.stream(buf, "second", "  ")
  render.stream(buf, " third", "  ")
  render.stream(buf, "\nnext", "  ")
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local joined = table.concat(lines, "|")
  h.ok(joined:match("  firstsecond third|  next"),
    "indent only at line start; got: " .. vim.inspect(lines))
end)

h.t("stream honors embedded newlines", function()
  local buf = h.new_buf()
  render.setup(buf)
  render.begin_message(buf, "assistant", "00:00")
  render.begin_text(buf)
  render.stream(buf, "line1\nline2")
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  h.ok(vim.tbl_contains(lines, "line1") and vim.tbl_contains(lines, "line2"),
    "multi-line delta splits into lines: " .. vim.inspect(lines))
end)

h.t("set_header formats winbar", function()
  local buf = h.new_buf()
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", row = 0, col = 0, width = 80, height = 5, style = "minimal",
  })
  render.set_header(win, { model = "gpt-4o", thinking_level = "low", status = "idle", session_name = "work" })
  local wb = vim.wo[win].winbar or ""
  h.ok(wb:match("gpt%-4o"), "model in winbar")
  h.ok(wb:match("low"), "thinking in winbar")
  vim.api.nvim_win_close(win, true)
end)
