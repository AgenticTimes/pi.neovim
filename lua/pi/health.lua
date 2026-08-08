-- lua/pi/health.lua — :checkhealth pi
local M = {}

function M.check()
  local ok_ver = vim.fn.has("nvim-0.10") == 1
  local ok_pi = false
  local version = ""
  if vim.fn.executable("pi") == 1 then
    local lines = vim.fn.system({ "pi", "--version" })
    version = lines:gsub("%s+$", "")
    ok_pi = true
  end
  if ok_ver then
    vim.health.ok(("Neovim %s (>= 0.10 required)"):format(vim.version().major .. "." .. vim.version().minor))
  else
    vim.health.error("Neovim >= 0.10 required, got " .. tostring(vim.version().major) .. "." .. tostring(vim.version().minor))
  end
  if ok_pi then
    vim.health.ok("pi CLI: " .. version)
  else
    vim.health.error("pi CLI not found in PATH; install with `npm i -g @earendil-works/pi-coding-agent`")
  end
end

return M
