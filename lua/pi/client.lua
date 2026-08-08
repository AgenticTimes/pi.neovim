-- lua/pi/client.lua — RPC 层：JSON 行 framing、请求关联、事件分发、job 生命周期
-- 注意：不用 vim.fn.jobstart 的 on_stdout（它会把输出按换行切分且偶发丢失换行符，破坏
-- JSONL framing）。改用 vim.uv.spawn + pipe read_start 读取原始字节流，自行 split_lines。
local config = require("pi.config")

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

-- —— job 生命周期（vim.uv 原始字节流） ——

local process = nil               -- uv.spawn handle
local pending = {}                -- id -> { cb, command, timer, pending_id }
local stdin_pipe = nil
local stderr_tail = {}            -- 最近若干行 stderr，诊断用
local partial_out = ""            -- 未完成 JSON 行累积（原始字节流，split_lines framing）
local callbacks = { on_event = nil, on_exit = nil, on_log = nil }

local function log(level, msg)
  if callbacks.on_log then callbacks.on_log(level, msg) end
end

local function dispatch_line(line)
  local ok, obj = pcall(vim.json.decode, line)
  if not ok or type(obj) ~= "table" then
    log("warn", "unparseable json line: " .. tostring(line))
    return
  end
  if obj.type == "response" then
    local rid = obj.id ~= nil and tostring(obj.id) or nil
    local entry
    if rid and pending[rid] then
      entry = pending[rid]
    elseif rid == nil then
      -- 无 id：先按 command 匹配唯一 pending，否则唯一 pending
      local cmd = obj.command
      local match
      for k, e in pairs(pending) do
        if cmd and e.command == cmd then
          if match then match = nil break end -- 多个 → 放弃
          match = e
        end
      end
      if not match then
        local single
        for _, e in pairs(pending) do
          if single then single = nil break end
          single = e
        end
        match = single
      end
      entry = match
    end
    if entry then
      local eid = entry.pending_id
      pending[eid] = nil
      if entry.timer then entry.timer:stop() end
      entry.cb(obj)
    else
      log("warn", "response with no matching request: " .. tostring(line))
    end
  else
    if callbacks.on_event then callbacks.on_event(obj) end
  end
end

local function on_stdout_data(err, data)
  if err then
    log("error", "stdout read error: " .. tostring(err))
    return
  end
  if data == nil then return end
  local lines
  lines, partial_out = M.split_lines(partial_out, data)
  if #lines == 0 then return end
  -- uv 回调是 fast event context，buffer API（渲染/autocmd）会抛 E5560 → 推迟到主循环
  vim.schedule(function()
    for _, line in ipairs(lines) do
      dispatch_line(line)
    end
  end)
end

local function on_stderr_data(err, data)
  if err or data == nil then return end
  for line in (data .. "\n"):gmatch("(.-)\n") do
    if #line > 0 then
      table.insert(stderr_tail, line)
      if #stderr_tail > 50 then table.remove(stderr_tail, 1) end
    end
  end
  log("error", data)
end

local function on_process_exit(handle, stdin, code, signal)
  -- 只清理属于本进程的状态（旧进程迟到的退出回调不得误清新进程）
  local was_this = process == handle
  if was_this then
    process = nil
  end
  if stdin_pipe == stdin then
    pcall(function() stdin_pipe:close() end)
    stdin_pipe = nil
  end
  -- 残留未完成行（进程退出前未换行的输出）
  if #partial_out > 0 then
    local line = partial_out
    partial_out = ""
    if #line > 0 then
      vim.schedule(function() dispatch_line(line) end)
    end
  end
  -- 未完成的请求 → 报错（只清属于本进程的请求）
  for id, e in pairs(pending) do
    if e.process == handle then
      if e.timer then e.timer:stop() end
      e.cb(nil, "pi process exited (code=" .. tostring(code) .. " signal=" .. tostring(signal) .. ")")
      pending[id] = nil
    end
  end
  if callbacks.on_exit and was_this then
    callbacks.on_exit(code, signal)
  end
end

function M.start(opts)
  opts = opts or {}
  -- 单例：已有进程先停掉（旧进程的迟到退出回调由身份守卫隔离）
  if M.is_running() then
    M.stop()
  end
  callbacks.on_event = opts.on_event
  callbacks.on_exit = opts.on_exit
  callbacks.on_log = opts.on_log
  stderr_tail = {}
  partial_out = ""
  local cwd = opts.cwd or vim.fn.getcwd()
  local cmd = opts.cmd or {}
  if #cmd == 0 then
    log("error", "start: empty cmd")
    return false
  end
  local file = cmd[1]
  local args = { unpack(cmd, 2) }
  local stdin = vim.uv.new_pipe(false)
  local stdout = vim.uv.new_pipe(false)
  local stderr = vim.uv.new_pipe(false)
  local handle, pid = vim.uv.spawn(file, {
    args = args,
    cwd = cwd,
    stdio = { stdin, stdout, stderr },
  }, function(code, signal)
    on_process_exit(handle, stdin, code, signal)
  end)
  if not handle then
    log("error", "failed to start pi: " .. tostring(file))
    return false
  end
  process = handle
  stdin_pipe = stdin
  vim.uv.read_start(stdout, on_stdout_data)
  vim.uv.read_start(stderr, on_stderr_data)
  return true
end

function M.stop()
  if process then
    local p = process
    process = nil
    if stdin_pipe then
      pcall(function() stdin_pipe:close() end)
      stdin_pipe = nil
    end
    pcall(function() p:kill(15) end)
    pcall(function() p:close() end)
  end
end

function M.is_running()
  return process ~= nil
end

local function send_raw(payload)
  if not stdin_pipe then return end
  pcall(function()
    stdin_pipe:write(payload)
  end)
end

function M.notify(type, params)
  if not M.is_running() then
    log("error", "notify while pi not running: " .. tostring(type))
    return
  end
  send_raw(M.build_request(M.next_id(), type, params))
end

function M.request(type, params, cb, timeout_seconds)
  if not M.is_running() then
    if cb then cb(nil, "pi not running") end
    return
  end
  local id = M.next_id()
  local key = tostring(id)
  local timeout = timeout_seconds or config.get().rpc_timeout
  local entry = { cb = cb or function() end, command = type, pending_id = key, process = process }
  if timeout and timeout > 0 then
    entry.timer = vim.uv.new_timer()
    entry.timer:start(math.floor(timeout * 1000), 0, function()
      entry.timer:stop()
      if pending[key] then
        pending[key] = nil
        entry.cb(nil, "rpc timeout for " .. tostring(type))
      end
    end)
  end
  pending[key] = entry
  send_raw(M.build_request(id, type, params))
end

---stderr 尾部（诊断用）。
function M.stderr_tail()
  return stderr_tail
end

return M
