local h = require("helpers")
local context = require("pi.context")

local fake = {
  ["@this"] = function() return "LINE" end,
  ["@buffer"] = function() return "BUF" end,
}

h.t("expand substitutes known placeholders and leaves unknown tokens", function()
  local out = context.expand("see @this and @nope here", fake)
  h.eq(out, "see LINE and @nope here")
end)

h.t("expand handles no placeholders and empty input", function()
  h.eq(context.expand("plain text", fake), "plain text")
  h.eq(context.expand("", fake), "")
end)

h.t("expand is word-boundary aware", function()
  h.eq(context.expand("@thisfoo", fake), "@thisfoo")
  h.eq(context.expand("(@this)", fake), "(LINE)")
end)

h.t("default getters return strings from the live buffer", function()
  local buf = h.new_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "beta" })
  local win = vim.api.nvim_open_win(buf, false, { relative = "editor", row = 0, col = 0, width = 80, height = 5, style = "minimal" })
  vim.api.nvim_win_set_cursor(win, { 2, 0 })
  local g = context.default_getters()
  h.ok((g["@this"]():match("beta")), "@this returns current line")
  h.ok((g["@buffer"]():match("alpha")), "@buffer returns buffer text")
  vim.api.nvim_win_close(win, true)
end)
