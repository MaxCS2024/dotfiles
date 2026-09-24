return {
  {
    "Mofiqul/vscode.nvim",
    lazy = false,
    priority = 1000,
    opts = function()
      local c = require("vscode.colors").get_colors()
      return {
        style = "dark",
        -- No background of its own: the terminal's shows through, which is
        -- the palette the shell writes out (foot, kitty, ghostty).
        transparent = true,
        italic_comments = true,
        -- `transparent` only clears the editor; popups, the completion menu
        -- and the status/tab lines still paint VSCode's grays. Floats are
        -- told apart by their border instead.
        group_overrides = {
          NormalFloat = { bg = "NONE" },
          FloatBorder = { fg = c.vscLineNumber, bg = "NONE" },
          Pmenu = { fg = c.vscPopupFront, bg = "NONE" },
          StatusLine = { fg = c.vscFront, bg = "NONE" },
          StatusLineNC = { fg = c.vscFront, bg = "NONE" },
          TabLine = { fg = c.vscFront, bg = "NONE" },
          TabLineFill = { fg = c.vscFront, bg = "NONE" },
          TabLineSel = { fg = c.vscFront, bg = "NONE", bold = true },
          WinBar = { fg = c.vscFront, bg = "NONE", bold = true },
          WinBarNC = { fg = c.vscFront, bg = "NONE" },
        },
      }
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "vscode" },
  },
}
