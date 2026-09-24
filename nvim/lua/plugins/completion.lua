-- LazyVim completes with blink.cmp; these are the old nvim-cmp keys and
-- window sizes. <CR> accepts and <C-Space> opens the menu already.
return {
  "saghen/blink.cmp",
  opts = {
    keymap = {
      ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
      ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
    },
    completion = {
      -- Borders, because the menus have no background of their own
      -- (plugins/colorscheme.lua).
      menu = { max_height = 8, border = "rounded" },
      documentation = {
        window = { max_height = 8, max_width = 50, border = "rounded" },
      },
    },
  },
}
