local h = require("helpers")
local client = require("pi.client")
local input = require("pi.input")
local session = require("pi.session")
local root = vim.fn.getcwd()

local function start_fake()
  client.start({ cmd = { "node", root .. "/tests/fake_pi.mjs" }, cwd = root,
    on_event = function() end })
  h.wait(3000, function() return client.is_running() end, "fake pi up")
end

h.t("get/set text round-trip", function()
  local buf = h.new_buf()
  input.setup(buf)
  input.set_text("hello")
  h.eq(input.get_text(), "hello")
end)

h.t("send submits prompt when idle and expands contexts", function()
  local buf = h.new_buf()
  input.setup(buf)
  start_fake()
  local sent = {}
  local orig_request = client.request
  client.request = function(type, params)
    table.insert(sent, { type = type, message = params.message })
    return orig_request(type, params, function() end)
  end
  session.reset({})
  input.set_text("@this hi")
  input.send()
  h.wait(3000, function() return #sent > 0 end, "request recorded")
  h.eq(sent[1].type, "prompt")
  h.ok(sent[1].message:match("hi"), "text sent")
  h.eq(input.get_text(), "", "input cleared after send")
  client.request = orig_request
  client.stop()
end)

h.t("send queues follow_up while busy", function()
  start_fake()
  local sent = {}
  local orig_request = client.request
  client.request = function(type, params)
    table.insert(sent, type)
    return orig_request(type, params, function() end)
  end
  session.reset({})
  session.set_local_status("streaming")
  input.set_text("second")
  input.send()
  h.wait(3000, function() return #sent > 0 end, "request recorded")
  h.eq(sent[1], "follow_up")
  client.request = orig_request
  client.stop()
end)

h.t("history cycles through previous prompts", function()
  local buf = h.new_buf()
  input.setup(buf)
  input.set_text("one")
  input.send() -- 空 client 也会记历史；send 在未启动 client 时不应崩溃
  input.set_text("two")
  input.send()
  input.set_text("three")
  input.send()
  input.history(-1)
  h.eq(input.get_text(), "two")
  input.history(-1)
  h.eq(input.get_text(), "one")
  input.history(1)
  h.eq(input.get_text(), "two")
end)
