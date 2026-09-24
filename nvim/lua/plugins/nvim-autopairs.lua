-- plugins/nvim-autopairs.lua

local autopairs_ok, npairs = pcall(require, "nvim-autopairs")
if not autopairs_ok then
  return
end

npairs.setup({
  check_ts = true, -- use treesitter
  disable_filetype = { "TelescopePrompt", "vim" },
  fast_wrap = {
    map = "<M-e>",
    chars = { "{", "[", "(", '"', "'" },
    pattern = [=[[%'%"%>%]%)%}%,]]=],
    end_key = "$",
    keys = "qwertyuiopzxcvbnmasdfghjkl",
    check_comma = true,
    highlight = "Search",
    highlight_grey = "Comment",
  },
})

-- =====================================================
-- nvim-cmp integration
-- =====================================================
local cmp_ok, cmp = pcall(require, "cmp")
if cmp_ok then
  local cmp_autopairs = require("nvim-autopairs.completion.cmp")

  cmp.event:on(
    "confirm_done",
    cmp_autopairs.on_confirm_done()
  )
end


