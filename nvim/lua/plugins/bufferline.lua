-- LazyVim ships bufferline; these are merged over its options.
return {
  "akinsho/bufferline.nvim",
  opts = {
    options = {
      themable = true,
      numbers = "none",
      show_buffer_close_icons = true,
      show_close_icon = true,
      separator_style = "thin",
      always_show_bufferline = true,
    },
    -- The bar takes the editor's background instead of its own shade.
    highlights = {
      fill = { bg = "NONE" },
      background = { bg = "NONE" },
      tab = { bg = "NONE" },
      tab_selected = { bg = "NONE", bold = true },
    },
  },
}
