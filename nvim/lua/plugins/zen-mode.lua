require("zen-mode").setup({
  window = {
    backdrop = 0.95,
    width = 80,
    height = 1,
    options = {
      signcolumn = "no",
      number = false,
      relativenumber = false,
      cursorline = false,
      cursorcolumn = false,
      foldcolumn = "0",
      list = false,

      wrap = true,
      linebreak = true,
      breakindent = false,
      showbreak = "",
    },
  },
  plugins = {
    options = {
      enabled = true,
      ruler = false,
      showcmd = false,
    },
    twilight = { enabled = true },
    gitsigns = { enabled = false },
    tmux = { enabled = true },
  },
  on_open = function()
    local ext = vim.fn.expand("%:e")
    if ext == "txt" then
      vim.opt_local.textwidth = 80
      vim.opt_local.formatoptions:append("t")
      -- reformat the whole buffer
      vim.cmd("silent! normal! ggVGgq")
    end
  end,
  on_close = function()
    local ext = vim.fn.expand("%:e")
    if ext == "txt" then
      vim.opt_local.textwidth = 0
      vim.opt_local.formatoptions:remove("t")
    end
  end,
})

