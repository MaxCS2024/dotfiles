return {
  {
    "Mofiqul/vscode.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "dark",
      -- No background of its own: the terminal's shows through, which is
      -- the palette the shell writes out (foot, kitty, ghostty).
      transparent = true,
      italic_comments = true,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "vscode" },
  },
}
