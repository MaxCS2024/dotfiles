return {
{
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  config = function()
    require'nvim-treesitter.configs'.setup {
      ensure_installed = { "lua", "python", "html", "css" }, -- pick your languages
      highlight = { enable = true },
      indent = { enable = true },
    }
  end
},
}


