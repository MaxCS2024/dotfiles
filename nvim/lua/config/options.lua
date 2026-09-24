-- Loaded before lazy.nvim starts, on top of LazyVim's defaults
-- (https://www.lazyvim.org/configuration/general). Only what differs from
-- them is here: number, relativenumber, wrap, ignorecase, smartcase,
-- cursorline, undofile, splitright, splitbelow and the system clipboard
-- are already LazyVim's.

vim.g.maplocalleader = " "

-- LazyVim formats on save; the old config never did. <leader>uf turns it on.
vim.g.autoformat = false

vim.o.tabstop = 4
vim.o.shiftwidth = 4
vim.o.expandtab = false
vim.o.swapfile = false
