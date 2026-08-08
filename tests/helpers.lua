-- tests/helpers.lua — 极简测试助手（零依赖）
local M = { tests = {} }

function M.t(name, fn)
  table.insert(M.tests, { name = name, fn = fn })
end

function M.eq(a, b, label)
  local same
  if type(a) == "table" and type(b) == "table" then
    same = vim.deep_equal(a, b)
  else
    same = (a == b)
  end
  if not same then
    error(("assert_eq failed%s: expected %s, got %s")
      :format(label and (" " .. label) or "", vim.inspect(b), vim.inspect(a)), 2)
  end
end

function M.ok(cond, label)
  if not cond then
    error("assert_ok failed: " .. (label or ""), 2)
  end
end

---等待直到 COND 为真或超时；超时则报错。
---@param ms integer
---@param cond function
---@param label string|nil
---@param interval integer|nil
function M.wait(ms, cond, label, interval)
  local ok = vim.wait(ms, cond, interval or 10)
  if not ok then
    error("wait timeout (" .. (label or "unnamed") .. ")", 2)
  end
end

---创建一个 scratch buffer（可写、nofile）。
function M.new_buf()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].buftype = "nofile"
  return buf
end

return M
