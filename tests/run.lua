-- tests/run.lua — headless 测试入口
-- 用法（仓库根目录）：nvim --headless -u NONE -i NONE -l tests/run.lua
-- 加载 tests/*_test.lua，运行 helpers.tests 注册的全部用例，非零退出表示失败。
package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. vim.fn.getcwd() .. "/tests/?.lua;" .. package.path

local helpers = require("helpers")
local files = vim.fn.glob(vim.fn.getcwd() .. "/tests/*_test.lua", false, true)
table.sort(files)

local load_failures = {}
for _, f in ipairs(files) do
  local ok, err = pcall(dofile, f)
  if not ok then
    table.insert(load_failures, f .. ": " .. tostring(err))
  end
end

local pass, fail = 0, 0
for _, tcase in ipairs(helpers.tests) do
  local ok, err = pcall(tcase.fn)
  if ok then
    pass = pass + 1
    print("OK   " .. tcase.name)
  else
    fail = fail + 1
    print("FAIL " .. tcase.name .. " :: " .. tostring(err))
  end
end

print(("SMOKE: %d passed, %d failed"):format(pass, fail))
for _, e in ipairs(load_failures) do
  print("LOAD FAIL " .. e)
end
os.exit((fail > 0 or #load_failures > 0) and 1 or 0)
