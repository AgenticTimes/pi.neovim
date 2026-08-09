local h = require("helpers")
local client = require("pi.client")
local root = vim.fn.getcwd()

local function fake_cmd(scenario)
  local args = { "node", root .. "/tests/fake_pi.mjs" }
  if scenario then table.insert(args, root .. "/tests/fixtures/" .. scenario) end
  return args
end

h.t("start + get_state round-trip", function()
  local events = {}
  local started = client.start({
    cmd = fake_cmd(),
    cwd = root,
    on_event = function(ev) table.insert(events, ev.type) end,
  })
  h.ok(started, "job starts")
  h.wait(3000, function() return client.is_running() end, "job running")

  local done = false
  local resp, err
  client.request("get_state", {}, function(r, e) resp, err = r, e; done = true end)
  h.wait(3000, function() return done end, "get_state response")
  h.eq(err, nil)
  h.ok(resp.success, "response success")
  h.eq(resp.data.sessionId, "fake-session")

  client.stop()
  h.wait(3000, function() return not client.is_running() end, "job stopped")
end)

h.t("prompt emits agent_start/end events", function()
  local events = {}
  client.start({ cmd = fake_cmd(), cwd = root, on_event = function(ev) table.insert(events, ev.type) end })
  h.wait(3000, function() return client.is_running() end, "job running")

  local done = false
  client.request("prompt", { message = "hi" }, function() done = true end)
  h.wait(3000, function() return done end, "prompt response")
  h.wait(3000, function() return events[#events] == "agent_settled" end, "events arrived")
  h.eq(events[1], "agent_start")
  h.eq(events[#events], "agent_settled")
  h.ok(vim.tbl_contains(events, "message_update"), "streaming deltas present")

  client.stop()
end)

h.t("request times out when pi never responds", function()
  -- scenario 不提供 get_state → fake pi 不回包 → 应超时回调 (nil, err)
  client.start({ cmd = fake_cmd("simple.json"), cwd = root })
  h.wait(3000, function() return client.is_running() end, "job running")

  local done = false
  local resp, err
  client.request("get_state", {}, function(r, e) resp, err = r, e; done = true end, 1)
  h.wait(3000, function() return done end, "timeout fired")
  h.eq(resp, nil)
  h.ok(err and err ~= "", "timeout error message present")
  client.stop()
end)

h.t("start fails gracefully when executable is missing", function()
  local logs = {}
  local ok = client.start({ cmd = { "definitely-not-a-real-binary-xyz" }, cwd = root,
    on_log = function(lvl, msg) table.insert(logs, lvl .. ":" .. msg) end })
  h.eq(ok, false)
  h.ok(#logs > 0, "error logged")
end)
