-- lua/pi/config.lua — 默认配置与用户 opts 合并（深合并，table 递归）
local M = {}

local defaults = {
  executable = "pi",            -- pi CLI 命令名（或绝对路径）
  window = {
    width = 0.85,               -- 相对 columns 的比例
    height = 0.85,              -- 相对 lines 的比例
    border = "rounded",
  },
  keys = {
    send = "<CR>",
    steer = "<C-s>",
    abort = "<C-c>",
    clear = "<C-k>",
    history_prev = "<M-p>",
    history_next = "<M-n>",
    close = "q",
    complete = "<Tab>",
  },
  rpc_timeout = 30,             -- 秒
  thinking_fold_delay = 3000,   -- ms；thinking 结束后自动折叠的延迟（0 = 不自动折叠）
  log_level = "warn",
  contexts = {},                -- 自定义上下文占位符 { ["@name"] = function() -> string }
}

local merged

local function deep_merge(base, over)
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over) do
    if type(v) == "table" and type(base[k]) == "table" then
      out[k] = deep_merge(base[k], v)
    else
      out[k] = v
    end
  end
  return out
end

function M.setup(opts)
  merged = deep_merge(defaults, opts or {})
end

function M.get()
  return merged
end

-- 默认值始终可用（未调用 setup 时）
M.setup({})

return M
