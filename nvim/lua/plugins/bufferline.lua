-- lua/plugins/bufferline.lua
-- Configuration for bufferline.nvim

-- Make sure bufferline is available
local ok, bufferline = pcall(require, "bufferline")
if not ok then
  return
end

bufferline.setup {
  options = {
	themable = true,
    mode = "buffers",                -- show buffers instead of tabpages
    numbers = "none",                -- hide buffer numbers
    diagnostics = "nvim_lsp",        -- show LSP diagnostics
    show_buffer_close_icons = true, -- hide buffer close icons
    show_close_icon = true,
    separator_style = "thin",       -- "slant", "thick", "thin", "padded_slant"
    always_show_bufferline = true,
    offsets = {
      {
        filetype = "NvimTree",
        text = "File Explorer",
        text_align = "center",
        separator = true,
      },
    },
  },
}

vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    vim.api.nvim_set_hl(0, "BufferLineFill", { bg = "NONE" })
    vim.api.nvim_set_hl(0, "BufferLineBackground", { bg = "NONE" })
    vim.api.nvim_set_hl(0, "BufferLineTab", { bg = "NONE" })
    vim.api.nvim_set_hl(0, "BufferLineTabSelected", { bg = "NONE", bold = true })
  end,
})

