-- disable netrw at the very start
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- enable 24-bit colors
vim.opt.termguicolors = true

-- setup nvim-tree
require("nvim-tree").setup({
  sort = {
    sorter = "case_sensitive",
  },
  view = {
    width = 30,
  },
  renderer = {
    group_empty = true,
  },
  filters = {
    dotfiles = true,
  },
  respect_buf_cwd = true,
  update_focused_file = {
    enable = true,
    update_root = true, -- make tree follow the file you open
  },
})

-- autocmd to hide UI clutter inside NvimTree
vim.api.nvim_create_autocmd("FileType", {
  pattern = "NvimTree",
  callback = function()
    vim.opt_local.cursorline = false
    vim.opt_local.cursorcolumn = false
    vim.opt_local.signcolumn = "no"
    -- if you also want to hide the cursor itself, uncomment below:
    -- vim.opt_local.guicursor = "a:Invisible"
  end,
})

