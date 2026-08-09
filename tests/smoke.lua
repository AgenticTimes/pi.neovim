-- tests/smoke.lua — pi.neovim 冒烟测试（独立运行）
-- 用法: nvim --headless -u NONE -i NONE -l tests/smoke.lua
local results = { pass = 0, fail = 0 }
local function check(label, cond)
  if cond then results.pass = results.pass + 1 print("SMOKE OK   " .. label)
  else results.fail = results.fail + 1 print("SMOKE FAIL " .. label) end
end
package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path
local ok_pi = pcall(require, "pi")
check("require pi", ok_pi)
local ok_health = pcall(require, "pi.health")
check("require pi.health", ok_health)
if results.fail == 0 then
  print("SMOKE_PASS")
  os.exit(0)
else
  print("SMOKE_FAIL")
  vim.cmd("cquit")
end
