-- Loading plugins with vim-plug 
local data_dir = vim.fn.stdpath('data')
if vim.fn.empty(vim.fn.glob(data_dir .. '/site/autoload/plug.vim')) == 1 then
		vim.cmd('silent !curl -fLo ' .. data_dir .. '/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim')
		vim.o.runtimepath = vim.o.runtimepath
		vim.cmd('autocmd VimEnter * PlugInstall --sync | source $MYVIMRC')
end

local Plug = vim.fn['plug#']

vim.call('plug#begin')

Plug('Mofiqul/vscode.nvim')

Plug('echasnovski/mini.icons')
Plug('mbbill/undotree')
Plug('nvim-lua/plenary.nvim')
Plug('nvim-tree/nvim-web-devicons')
Plug('nvim-tree/nvim-tree.lua')
Plug('nvim-telescope/telescope.nvim')
Plug('nvim-treesitter/nvim-treesitter')
Plug('folke/which-key.nvim')
Plug('windwp/nvim-autopairs')
Plug('lukas-reineke/indent-blankline.nvim')
Plug('akinsho/bufferline.nvim')


Plug('folke/twilight.nvim')
Plug('folke/zen-mode.nvim')


Plug('mason-org/mason.nvim')
Plug('mason-org/mason-lspconfig.nvim')
Plug('neovim/nvim-lspconfig')


Plug('hrsh7th/nvim-cmp')
Plug('hrsh7th/cmp-nvim-lsp')
Plug('hrsh7th/cmp-buffer')
Plug('hrsh7th/cmp-path')

Plug('L3MON4D3/LuaSnip')
Plug('saadparwaiz1/cmp_luasnip')


vim.call('plug#end')


require("config.options")
require("config.keymaps")
require("config.colorscheme")

require('plugins.mason')
require('plugins.zen-mode')
require('plugins.nvim-cmp')
require('plugins.nvim-tree')
require('plugins.indent-blankline')
require('plugins.bufferline')
require('plugins.nvim-autopairs')
