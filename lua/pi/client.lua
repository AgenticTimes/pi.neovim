-- lua/pi/client.lua — RPC 层：JSON 行 framing、请求关联、事件分发、job 生命周期
local M = {}
local id_counter = 0

---按行切分：把 CHUNK 拼到 REMAINDER 上，返回完整行列表 + 新的不完整尾部。
---每 chunk 只做一次字符串累积（不反复 concat 整个部分行）。
function M.split_lines(remainder, chunk)
  local acc = remainder .. chunk
  local lines = {}
  local start = 1
  while true do
    local nl = string.find(acc, "\n", start, true)
    if not nl then break end
    local line = string.sub(acc, start, nl - 1)
    if #line > 0 then
      table.insert(lines, line)
    end
    start = nl + 1
  end
  return lines, string.sub(acc, start)
end

---构造带 id/type/params 的请求行（以 \n 结尾）。
function M.build_request(id, type, params)
  local obj = { id = id, type = type }
  if params then
    for k, v in pairs(params) do obj[k] = v end
  end
  return vim.json.encode(obj) .. "\n"
end

function M.next_id()
  id_counter = id_counter + 1
  return id_counter
end

return M
