local h = require("helpers")
local client = require("pi.client")

h.t("split_lines handles complete and partial lines", function()
  local lines, rem = client.split_lines("", '{"a":1}\n{"b":2}\n')
  h.eq(lines, { '{"a":1}', '{"b":2}' })
  h.eq(rem, "")
end)

h.t("split_lines keeps partial tail in remainder", function()
  local lines, rem = client.split_lines("", '{"a":1}\n{"b":')
  h.eq(lines, { '{"a":1}' })
  h.eq(rem, '{"b":')
end)

h.t("split_lines continues across chunks without concat blowup", function()
  local rem = ""
  local all = {}
  for i = 1, 1000 do
    local lines
    lines, rem = client.split_lines(rem, "x") -- 一个字符一个 chunk
    for _, l in ipairs(lines) do table.insert(all, l) end
  end
  -- 最后一行是 1000 个 x，未换行 → 全部在 remainder
  h.eq(#all, 0)
  h.eq(rem, string.rep("x", 1000))
end)

h.t("build_request embeds id/type/params", function()
  local s = client.build_request(7, "prompt", { message = "hi" })
  h.eq(s:sub(-1), "\n", "newline terminated")
  local obj = vim.json.decode(s)
  h.eq(obj.id, 7)
  h.eq(obj.type, "prompt")
  h.eq(obj.message, "hi")
end)

h.t("next_id is monotonic", function()
  local a, b = client.next_id(), client.next_id()
  h.ok(b > a, "ids increase")
end)
