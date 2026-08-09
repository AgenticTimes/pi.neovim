-- lua/pi/config.lua — 默认配置与用户 opts 合并（深合并，table 递归）
local M = {}

local defaults = {
  executable = "pi",            -- pi CLI 命令名
  window = {
    width = 0.85,               -- float 宽度（相对 columns）
    height = 0.85,              -- float 高度（相对 lines）
    border = "rounded",
  },
  warm_start = false,           -- 后台预热：空闲时提前启动 pi（首次打开秒开）
  warm_start_delay = 2000,      -- ms；预热延迟（VimEnter 后多久启动 pi）
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
