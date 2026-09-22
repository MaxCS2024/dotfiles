-- lua/plugins/mason.lua

-- Load Mason and Mason-LSPConfig
local mason = require("mason")
local mason_lspconfig = require("mason-lspconfig")

mason.setup()

mason_lspconfig.setup({
  ensure_installed = { "lua_ls", "pyright" },
  automatic_installation = true,
})

-- Detect the correct API for your Neovim version
local ok, configs = pcall(function()
  return vim.lsp.configs or vim.lsp._configs or vim.lsp.config
end)
if not ok or not configs then
  vim.notify("Could not load vim.lsp.configs; please update Neovim", vim.log.levels.ERROR)
  return
end

-- Define LSP server configurations (new API)
configs.lua_ls = {
  default_config = {
    cmd = { "lua-language-server" },
    filetypes = { "lua" },
    root_dir = vim.fs.root(0, { ".git", ".luarc.json", ".luacheckrc" }),
    settings = {
      Lua = {
        diagnostics = { globals = { "vim" } },
        workspace = { checkThirdParty = false },
      },
    },
  },
}

configs.pyright = {
  default_config = {
    cmd = { "pyright-langserver", "--stdio" },
    filetypes = { "python" },
    root_dir = vim.fs.root(0, { ".git" }),
  },
}

-- Start each LSP
for _, server in ipairs({ "lua_ls", "pyright" }) do
  local conf = configs[server]
  if conf and conf.default_config then
    vim.lsp.start(conf.default_config)
  else
    vim.notify("No config found for " .. server, vim.log.levels.WARN)
  end
end

