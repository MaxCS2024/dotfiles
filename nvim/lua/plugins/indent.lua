-- LazyVim draws indent guides with snacks.indent, not indent-blankline.
return {
  "folke/snacks.nvim",
  opts = {
    indent = {
      indent = { char = "¦" },
    },
  },
}
