-- lua/pi/edits.lua — 编辑同步：tool 写文件后 reload buffer + :PiDiff
local session = require("pi.session")

local M = {}

local function norm(p)
  return vim.fn.fnamemodify(p, ":p")
end

function M.buffer_for(path)
  local abs = norm(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and norm(name) == abs then
        return buf
      end
    end
  end
  return nil
end

function M.reload_after(event)
  local id = event.toolCallId
  local tools = session.get().active_tools
  if id == nil or tools[id] == nil then return end
  local tool = tools[id]
  local a = tool.args or {}
  local f = a.file_path or a.path or a.filename
  if not f then return end
  local buf = M.buffer_for(f)
  if not buf then return end
  if vim.bo[buf].modified then
    vim.notify("pi changed " .. f .. " but buffer is modified; not reloading", vim.log.levels.WARN)
    return
  end
  vim.cmd("edit! " .. vim.fn.fnameescape(f))
end

local function git_root(file)
  local dir = vim.fn.fnamemodify(file, ":h")
  while dir ~= "/" and dir ~= "" do
    if vim.fn.isdirectory(dir .. "/.git") == 1 then return dir end
    dir = vim.fn.fnamemodify(dir, ":h")
  end
  return nil
end

function M.diff()
  local touched = session.touched_files()
  local text = {}
  local seen_roots = {}
  for _, f in ipairs(touched) do
    local root = git_root(f)
    if root and not seen_roots[root] then
      seen_roots[root] = true
      local rel = vim.fn.fnamemodify(f, ":t")
      local ok, status = pcall(vim.fn.system, { "git", "-C", root, "status", "--short", "--", rel })
      local ok2, diff = pcall(vim.fn.system, { "git", "-C", root, "diff", "--", rel })
      table.insert(text, "# " .. f)
      if ok and status ~= "" then table.insert(text, status) end
      if ok2 and diff ~= "" then table.insert(text, diff) end
    end
  end
  if #text == 0 then
    vim.notify("pi: no touched files yet this session", vim.log.levels.INFO)
    return nil
  end
  local buf = vim.fn.bufnr("pi://diff")
  if buf == -1 then
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "pi://diff")
    vim.bo[buf].buftype = "nofile"
  end
  vim.bo[buf].filetype = "diff"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(table.concat(text, "\n"), "\n", { plain = true }))
  return buf
end

return M
