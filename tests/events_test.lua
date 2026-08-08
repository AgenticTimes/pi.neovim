local h = require("helpers")
local events = require("pi.events")

h.t("registered callbacks fire with the event", function()
  local seen = {}
  local unsub = events.on("agent_start", function(ev) table.insert(seen, ev.type) end)
  events.dispatch({ type = "agent_start" })
  h.eq(seen, { "agent_start" })
  unsub()
  events.dispatch({ type = "agent_start" })
  h.eq(#seen, 1, "unsubscribed no longer fires")
end)

h.t("wildcard callback receives all events", function()
  local count = 0
  local unsub = events.on("*", function() count = count + 1 end)
  events.dispatch({ type = "message_start" })
  events.dispatch({ type = "message_end" })
  h.eq(count, 2)
  unsub()
end)

h.t("emit sets vim.g.pi_event and fires autocmd", function()
  local fired = 0
  vim.api.nvim_create_autocmd("User", {
    pattern = "PiEvent",
    callback = function() fired = fired + 1 end,
  })
  events.emit({ type = "agent_end", willRetry = false })
  h.eq(fired, 1)
  h.eq(vim.g.pi_event.type, "agent_end")
end)

h.t("dispatch updates session status", function()
  local session = require("pi.session")
  session.reset({})
  events.dispatch({ type = "agent_start" })
  h.eq(session.get().status, "streaming")
end)
