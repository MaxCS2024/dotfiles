-- lua/config/colorscheme.lua

-- Enable options BEFORE loading the colorscheme
vim.g.vscode_transparent = 0       -- transparent background
vim.g.vscode_italic_comment = 1    -- italic comments

vim.o.background = 'dark'
vim.opt.termguicolors = true

-- Load the colorscheme
vim.cmd([[colorscheme vscode]])

