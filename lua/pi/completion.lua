-- lua/pi/completion.lua — 输入区补全：slash 命令 / @文件引用 / 路径
local M = {}
local commands = {}   -- { { name=..., source=... }, ... }

---从 SKILL.md frontmatter 提取 name（fallback：首个 # 标题）。
local function parse_skill_name_impl(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local content = fh:read("*a")
  fh:close()
  local name = content:match("^%-%-%-%s*\nname:%s*([^\n]+)")
  if not name then name = content:match("^#+%s*([^\n]+)") end
  if not name then return nil end
  return name:gsub("^[%s'\"]+", ""):gsub("[%s'\"]+$", "")
end

M.parse_skill_name = parse_skill_name_impl

---本地兜底命令列表：~/.agents/skills/*/SKILL.md 与 ~/.pi/agent/prompts/*.md。
---当 RPC get_commands 返回空（某些环境/项目下）时保证 / 仍有候选。
function M.load_local_commands()
  local out = {}
  local skills_dir = vim.fn.expand("~/.agents/skills")
  if vim.fn.isdirectory(skills_dir) == 1 then
    for _, d in ipairs(vim.fn.glob(skills_dir .. "/*", false, true)) do
      if vim.fn.isdirectory(d) == 1 then
        local md = d .. "/SKILL.md"
        if vim.fn.filereadable(md) == 1 then
          local name = parse_skill_name_impl(md)
          if name then
            table.insert(out, { name = "skill:" .. name, source = "skill" })
          end
        end
      end
    end
  end
  local prompts_dir = vim.fn.expand("~/.pi/agent/prompts")
  if vim.fn.isdirectory(prompts_dir) == 1 then
    for _, f in ipairs(vim.fn.glob(prompts_dir .. "/*.md", false, true)) do
      table.insert(out, { name = vim.fn.fnamemodify(f, ":t:r"), source = "prompt" })
    end
  end
  return out
end

function M.set_commands(list)
  commands = {}
  local seen = {}
  for _, c in ipairs(list or {}) do
    if c and c.name and not seen[c.name] then
      seen[c.name] = true
      table.insert(commands, c)
    end
  end
  -- RPC 未覆盖的 skills/prompts 从文件系统补齐（去重）
  for _, c in ipairs(M.load_local_commands()) do
    if not seen[c.name] then
      seen[c.name] = true
      table.insert(commands, c)
    end
  end
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
  -- 原生 pi 行为：输入 / （命令位置）或 @ 自动弹出补全菜单
  vim.api.nvim_create_autocmd("InsertCharPre", {
    buffer = buf,
    callback = function()
      local ch = vim.v.char
      if ch == "/" then
        local line = vim.api.nvim_get_current_line()
        local col = vim.api.nvim_win_get_cursor(0)[2] -- 0-based
        local prev = (col > 0) and line:sub(col, col) or ""
        -- 仅当 / 位于行首或空白后（命令位置）才自动弹出；路径中的 / 交给 <Tab>
        if prev == "" or prev:match("%s") then
          vim.schedule(function() M.complete() end)
        end
      elseif ch == "@" then
        vim.schedule(function() M.complete() end)
      end
    end,
  })
end

return M
