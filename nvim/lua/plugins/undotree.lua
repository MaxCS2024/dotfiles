-- <leader>u is LazyVim's toggle menu, so undotree sits inside it.
return {
  "mbbill/undotree",
  keys = {
    { "<leader>uU", "<cmd>UndotreeToggle<cr>", desc = "Toggle Undotree" },
  },
}
