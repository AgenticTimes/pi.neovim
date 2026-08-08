-- lua/pi/context.lua — 上下文占位符展开（发送时调用）
local M = {}

local function current_line()
  return vim.fn.getline(".")
end

local function visual_selection()
  local m = vim.fn.mode()
  if m == "v" or m == "V" or m == "\22" then
    local s, e = vim.fn.getpos("'<"), vim.fn.getpos("'>")
    if s[1] == e[1] and s[2] == e[2] then
      return table.concat(vim.fn.getline(s[2], e[2]), "\n")
    end
  end
  return nil
end

local function buffer_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

function M.default_getters()
  local diag = function()
    local lines = {}
    for _, d in ipairs(vim.diagnostic.get(0)) do
      table.insert(lines, string.format("%s:%d:%d: %s",
        vim.fn.expand("%:p"), d.lnum + 1, (d.col or 0) + 1, d.message))
    end
    return table.concat(lines, "\n")
  end
  local visible = function()
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    local top = vim.fn.line("w0")
    local bot = vim.fn.line("w$")
    return table.concat(vim.api.nvim_buf_get_lines(buf, top - 1, bot, false), "\n")
  end
  return {
    ["@this"] = function()
      return visual_selection() or current_line()
    end,
    ["@buffer"] = function()
      return buffer_text(vim.api.nvim_get_current_buf())
    end,
    ["@buffers"] = function()
      local parts = {}
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          local name = vim.api.nvim_buf_get_name(buf)
          if name ~= "" then
            table.insert(parts, "### " .. name .. "\n" .. buffer_text(buf))
          end
        end
      end
      return table.concat(parts, "\n\n")
    end,
    ["@diagnostics"] = diag,
    ["@visible"] = visible,
  }
end

function M.expand(text, getters)
  getters = getters or vim.tbl_extend("force", M.default_getters(), require("pi.config").get().contexts or {})
  local out = text:gsub("(%f[%a@]@[%a_][%w_-]*)", function(tok)
    local fn = getters[tok]
    if not fn then return tok end
    local val = fn()
    if val == nil then return tok end
    return val
  end)
  return out
end

return M
