local h = require("helpers")
local completion = require("pi.completion")

h.t("current_token reads the word under cursor", function()
  local buf = h.new_buf()
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "type /co here" })
  vim.api.nvim_win_set_cursor(0, { 1, 7 })
  local token, start = completion._current_token()
  h.eq(token, "/co")
  h.eq(start, 5)
end)

h.t("slash completion builds items from commands", function()
  completion.set_commands({ { name = "compact", source = "prompt" }, { name = "clear", source = "prompt" } })
  local buf = h.new_buf()
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "/co" })
  vim.api.nvim_win_set_cursor(0, { 1, 3 })
  local token, start = completion._current_token()
  h.eq(token, "/co")
  local items = completion._slash_items("/co")
  h.eq(items[1].word, "/compact")
  h.eq(items[1].menu, "prompt")
end)

h.t("file references come from git ls-files", function()
  -- 当前 repo 是 pi.nvim 自己（git repo）→ ls-files 非空
  local files = completion.git_files()
  h.ok(type(files) == "table", "git_files returns a table")
  if #files > 0 then
    h.ok(type(files[1]) == "string" and files[1] ~= "", "entries are non-empty paths")
  end
end)

h.t("slash completion includes skills and prompt commands", function()
  completion.set_commands({
    { name = "compact", source = "prompt" },
    { name = "review", source = "skill" },
    { name = "edit", source = "extension" },
  })
  local items = completion._slash_items("/")
  local sources = {}
  for _, it in ipairs(items) do sources[it.word] = it.menu end
  h.eq(sources["/compact"], "prompt")
  h.eq(sources["/review"], "skill")
  h.eq(sources["/edit"], "extension")
end)

h.t("complete is safe with empty lists and unknown tokens", function()
  completion.set_commands({})
  local buf = h.new_buf()
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "plain text" })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  local ok = pcall(completion.complete)
  h.ok(ok, "complete with no candidates is safe")
end)
