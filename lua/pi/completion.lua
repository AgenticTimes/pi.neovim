-- lua/pi/completion.lua — 输入区补全：slash 命令 / @文件引用 / 路径
local M = {}
local commands = {}   -- { { name=..., source=... }, ... }

function M.set_commands(list)
  commands = list or {}
end

function M._current_token()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] -- 0-based
  local start = col
  while start > 0 do
    local c = line:sub(start, start)
    if c:match("%s") then break end
    start = start - 1
  end
  return line:sub(start + 1, col + 1), start
end

function M.git_files()
  local root = vim.fn.system({ "git", "-C", vim.fn.getcwd(), "rev-parse", "--show-toplevel" })
  root = root:gsub("%s+$", "")
  if root == "" then return {} end
  local out = vim.fn.system({ "git", "-C", root, "ls-files" })
  local files = {}
  for f in out:gmatch("[^\n]+") do table.insert(files, f) end
  return files
end

function M._slash_items(token)
  local items = {}
  local prefix = token:sub(2)
  for _, c in ipairs(commands) do
    if c.name:sub(1, #prefix) == prefix then
      table.insert(items, { word = "/" .. c.name, menu = c.source or "" })
    end
  end
  return items
end

function M._path_items(token)
  local items = {}
  local dir = token:match("(.*/)")
  if not dir then return items end
  local expanded = vim.fn.expand(dir .. "*")
  for p in expanded:gmatch("[^\n]+") do
    table.insert(items, { word = p })
  end
  return items
end

function M.complete()
  local token, start = M._current_token()
  local items = {}
  if token:sub(1, 1) == "/" then
    items = M._slash_items(token)
  elseif token:sub(1, 1) == "@" then
    local prefix = token:sub(2)
    for _, f in ipairs(M.git_files()) do
      if f:sub(1, #prefix) == prefix then
        table.insert(items, { word = "@" .. f })
      end
    end
  else
    items = M._path_items(token)
  end
  if #items > 0 then
    vim.fn.complete(start, items)
  end
end

function M.setup(buf)
  local keys = require("pi.config").get().keys
  vim.keymap.set("i", keys.complete, function() M.complete() end, { buffer = buf, desc = "pi: complete" })
end

return M
