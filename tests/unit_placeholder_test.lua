local h = require("helpers")
local pi = require("pi")

h.t("stub loads", function()
  h.eq(pi.name, "pi.neovim")
end)
