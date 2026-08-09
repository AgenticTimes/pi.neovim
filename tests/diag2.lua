-- tests/diag2.lua — 补全链路诊断（临时）
-- 用法: cd /tmp && nvim --headless -u ~/.config/nvim/init.lua -l ~/source/pi/pi.nvim/tests/diag2.lua
local out = {}
local function log(...)
  local parts = {}
  for _, v in ipairs({ ... }) do parts[#parts + 1] = tostring(v) end
  table.insert(out, table.concat(parts, " "))
end

log("== 补全链路诊断 ==")
local ok_pi, err_pi = pcall(require, "pi")
log("require pi:", tostring(ok_pi), err_pi or "")

if ok_pi then
  local ok_open, err_open = pcall(function() require("pi").toggle() end)
  log("toggle float:", tostring(ok_open), err_open or "")
  vim.wait(5000)
  local ui = require("pi.ui")
  local client = require("pi.client")
  log("float open:", tostring(ui.is_open()))
  log("client running:", tostring(client.is_running()))

  -- 拉 get_commands 并直接打印响应
  local got = false
  client.request("get_commands", {}, function(resp)
    if resp then
      log("get_commands success:", tostring(resp.success))
      local data = resp.data
      log("data 类型:", type(data), "数组长度:", type(data) == "table" and #data or "?")
      if type(data) == "table" then
        for i, c in ipairs(data) do
          if i <= 8 then log("  [" .. i .. "] name=" .. tostring(c.name) .. " source=" .. tostring(c.source)) end
        end
      end
    else
      log("get_commands 无响应/错误")
    end
    got = true
  end, 5)
  vim.wait(6000, function() return got end, 50)
  log("get_commands 返回:", tostring(got))

  -- 补全状态
  local completion = require("pi.completion")
  log("slash_items('/') 数量:", #completion._slash_items("/"))
  -- 输入区键位
  local ib = ui.input_buf()
  if ib then
    local kms = vim.api.nvim_buf_get_keymap(ib, "i")
    local cr = {}
    for _, m in ipairs(kms) do
      if m.lhs == "<Tab>" or m.lhs == "<CR>" then table.insert(cr, m.lhs .. "=" .. (m.callback and "fn" or "?")) end
    end
    log("input <Tab>/<CR> 键位:", vim.inspect(cr))
  end
end

local f = io.open(vim.fn.expand("~/pi-diag2.txt"), "w")
f:write(table.concat(out, "\n") .. "\n")
f:close()
print("=== 诊断已写入 ~/pi-diag2.txt ===")
