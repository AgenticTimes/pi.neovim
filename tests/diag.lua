-- tests/diag.lua — pi.nvim 诊断脚本（临时）
-- 用法: cd /tmp && nvim --headless -u ~/.config/nvim/init.lua -l ~/source/pi/pi.nvim/tests/diag.lua
local out = {}
local function log(...)
  local parts = {}
  for _, v in ipairs({ ... }) do parts[#parts + 1] = tostring(v) end
  table.insert(out, table.concat(parts, " "))
end

log("== pi.nvim 诊断 ==")
log("nvim:", vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch)
log("pi 可执行:", vim.fn.executable("pi"))
local ver = vim.fn.system({ "pi", "--version" })
log("pi 版本:", ver:gsub("%s+$", ""))

local ok_pi, err_pi = pcall(require, "pi")
log("require pi:", tostring(ok_pi), err_pi or "")

if ok_pi then
  local ok_open, err_open = pcall(function() require("pi").toggle() end)
  log("toggle float:", tostring(ok_open), err_open or "")
  vim.wait(5000)
  local ui = require("pi.ui")
  log("float open:", tostring(ui.is_open()))
  log("client running:", tostring(require("pi.client").is_running()))
  log("session:", vim.inspect(require("pi.session").get()))
  local chat = ui.chat_buf()
  if chat then
    local lines = vim.api.nvim_buf_get_lines(chat, 0, -1, false)
    log("chat 内容 (" .. #lines .. " 行):")
    for i, l in ipairs(lines) do log("  " .. i .. ": " .. l) end
  end
  local w = ui.chat_win()
  if w then log("winbar:", vim.wo[w].winbar or "") end
  log("stderr 尾部:", vim.inspect(require("pi.client").stderr_tail()))
end

local f = io.open(vim.fn.expand("~/pi-diag.txt"), "w")
f:write(table.concat(out, "\n") .. "\n")
f:close()
print("=== 诊断已写入 ~/pi-diag.txt ===")
