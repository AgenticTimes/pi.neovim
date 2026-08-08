-- lua/pi/session.lua — 会话状态机：状态迁移 + 状态存储
local M = {}

local state = {
  status = "idle",
  model = nil,
  thinking_level = nil,
  session_name = nil,
  session_id = nil,
  auto_compaction_enabled = nil,
  messages = {},
  current_message = nil,
  active_tools = {},   -- toolCallId -> { toolName, args }
  touched_files = {},  -- 本会话 pi 触碰过的文件（去重）
}

---纯函数：状态迁移。EVENT_TYPE + DATA -> 新状态。
function M.transition(status, event_type, data)
  data = data or {}
  if event_type == "agent_start" then
    return "streaming"
  elseif event_type == "agent_end" then
    return data.willRetry and "sending" or "idle"
  elseif event_type == "compaction_start" then
    return "compacting"
  elseif event_type == "compaction_end" then
    if data.willRetry or data.success then return "sending" end
    return "idle"
  elseif event_type == "auto_retry_start" then
    return "sending"
  elseif event_type == "auto_retry_end" then
    if not data.success and status == "sending" then return "idle" end
    return status
  end
  return status
end

function M.reset(s)
  s = s or {}
  state.status = (s.isStreaming and "streaming") or (s.isCompacting and "compacting") or "idle"
  state.model = s.model
  state.thinking_level = s.thinkingLevel
  state.session_name = s.sessionName
  state.session_id = s.sessionId
  state.auto_compaction_enabled = s.autoCompactionEnabled
  state.messages = s.messages or {}
  state.current_message = nil
  state.active_tools = {}
  state.touched_files = {}
end

function M.apply_event(event)
  if not event or not event.type then return end
  local t = event.type
  state.status = M.transition(state.status, t, event)
  if t == "agent_end" and event.messages then
    state.messages = event.messages
  end
  if t == "message_start" then
    state.current_message = event.message
  elseif t == "message_end" then
    state.current_message = nil
  elseif t == "tool_execution_start" then
    M.record_tool(event)
  elseif t == "tool_execution_end" then
    M.end_tool(event.toolCallId)
  end
  -- 从事件里同步可用字段
  if event.model then state.model = event.model end
  if event.thinkingLevel then state.thinking_level = event.thinkingLevel end
  if event.sessionName then state.session_name = event.sessionName end
end

function M.set_local_status(s)
  state.status = s
end

local function extract_file(event)
  local a = event.args or {}
  return a.file_path or a.path or a.filename or (a.paths and a.paths[1]) or nil
end

function M.record_tool(event)
  local id = event.toolCallId
  if id == nil then return end
  state.active_tools[id] = { toolName = event.toolName, args = event.args }
  local f = extract_file(event)
  if f then
    for _, existing in ipairs(state.touched_files) do
      if existing == f then return end
    end
    table.insert(state.touched_files, f)
  end
end

function M.end_tool(tool_call_id)
  if tool_call_id == nil then return end
  state.active_tools[tool_call_id] = nil
end

function M.get()
  return state
end

function M.touched_files()
  return state.touched_files
end

return M
