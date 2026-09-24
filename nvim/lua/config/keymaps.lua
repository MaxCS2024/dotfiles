-- Loaded on the VeryLazy event, after LazyVim's own keymaps
-- (https://www.lazyvim.org/keymaps), so anything here wins.
local map = vim.keymap
local opts = { noremap = true, silent = true }

-- Deleting and changing don't overwrite what was yanked; <leader>d still cuts.
map.set("x", "p", '"_dP')
map.set({ "n", "x" }, "d", '"_d')
map.set({ "n", "x" }, "c", '"_c')
map.set({ "n", "x" }, "<leader>d", "d")

-- Disables o and O from entering insert mode
map.set("n", "o", "o<Esc>", opts)
map.set("n", "O", "O<Esc>", opts)

-- Escape insert with jj
map.set("i", "jj", "<Esc>", { desc = "Exit insert mode", noremap = true, silent = true })

-- Disable arrow keys (no desc, since they don't need to show up in which-key)
for _, mode in ipairs({ "n", "i", "v" }) do
  for _, key in ipairs({ "<Up>", "<Down>", "<Left>", "<Right>" }) do
    map.set(mode, key, "<Nop>", opts)
  end
end

-- Window splits
map.set("n", "<leader>ws", "<C-w>s", { desc = "Split window horizontally", noremap = true, silent = true })
map.set("n", "<leader>wv", "<C-w>v", { desc = "Split window vertically", noremap = true, silent = true })
map.set("n", "<leader>wS", ":new<CR>", { desc = "New horizontal split", noremap = true, silent = true })
map.set("n", "<leader>wV", ":vnew<CR>", { desc = "New vertical split", noremap = true, silent = true })

-- Window closing/movement
map.set("n", "<leader>wc", "<C-w>c", { desc = "Close window", noremap = true, silent = true })
map.set("n", "<leader>wh", "<C-w>h", { desc = "Move left", noremap = true, silent = true })
map.set("n", "<leader>wl", "<C-w>l", { desc = "Move right", noremap = true, silent = true })
map.set("n", "<leader>wj", "<C-w>j", { desc = "Move down", noremap = true, silent = true })
map.set("n", "<leader>wk", "<C-w>k", { desc = "Move up", noremap = true, silent = true })

-- Buffers
map.set("n", "<Tab>", ":BufferLineCycleNext<CR>", { desc = "Next buffer", noremap = true, silent = true })
map.set("n", "<S-Tab>", ":BufferLineCyclePrev<CR>", { desc = "Prev buffer", noremap = true, silent = true })
map.set("n", "<leader>tn", ":enew<CR>", { desc = "New buffer", noremap = true, silent = true })
map.set("n", "<leader>tc", function()
  Snacks.bufdelete()
end, { desc = "Close buffer", noremap = true, silent = true })
map.set("n", "<leader>tp", ":BufferLinePick<CR>", { desc = "Pick buffer", noremap = true, silent = true })

-- Search for a typed string, as a literal rather than a pattern.
-- <leader>ff (find files) and <leader>e (explorer) are LazyVim's own.
map.set("n", "<leader>fs", function()
  Snacks.picker.grep({ search = vim.fn.input("Grep > "), regex = false })
end, { desc = "Search string", noremap = true, silent = true })
