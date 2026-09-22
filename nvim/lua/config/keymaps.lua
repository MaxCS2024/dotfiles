local wk = require("which-key")

local map = vim.keymap
local opts = { noremap = true, silent = true }

map.set("x", "p", '"_dP')
map.set({"n", "x"}, "d", '"_d')
map.set({"n", "x"}, "c", '"_c')
map.set({"n", "x"}, "<leader>d", "d")

wk.add({
  { "<leader>w", group = "[w]indows" },
  { "<leader>t", group = "[t]abs/buffers" },
  { "<leader>f", group = "[s]earch" },
  { "<leader>e", group = "[e]xplorer" },
  { "<leader>u", group = "[u]ndotree" },
  { "<leader>p", group = "[c]ode"},
  --{ "<leader>y", group = "clipboard" },
  --{ "<leader>p", group = "clipboard" },
})


-- Disables o and O from entering insert mode
map.set('n', 'o', 'o<Esc>', opts)
map.set('n', 'O', 'O<Esc>', opts)

-- Escape insert with jj
map.set('i', 'jj', '<Esc>', { desc = "Exit insert mode", noremap = true, silent = true })

-- Disable arrow keys (no desc, since they don't need to show up in which-key)
map.set('n', '<Up>', '<Nop>',    opts)
map.set('n', '<Down>', '<Nop>',  opts)
map.set('n', '<Left>', '<Nop>',  opts)
map.set('n', '<Right>', '<Nop>', opts)

map.set('i', '<Up>', '<Nop>',    opts)
map.set('i', '<Down>', '<Nop>',  opts)
map.set('i', '<Left>', '<Nop>',  opts)
map.set('i', '<Right>', '<Nop>', opts)

map.set('v', '<Up>', '<Nop>',    opts)
map.set('v', '<Down>', '<Nop>',  opts)
map.set('v', '<Left>', '<Nop>',  opts)
map.set('v', '<Right>', '<Nop>', opts)

-- Window splits
map.set('n', '<leader>ws', '<C-w>s',    { desc = "Split window horizontally", noremap = true, silent = true })
map.set('n', '<leader>wv', '<C-w>v',    { desc = "Split window vertically",   noremap = true, silent = true })
map.set('n', '<leader>wS', ':new<CR>',  { desc = "New horizontal split",      noremap = true, silent = true })
map.set('n', '<leader>wV', ':vnew<CR>', { desc = "New vertical split",        noremap = true, silent = true })

-- Window closing/movement
map.set('n', '<leader>wc', '<C-w>c', { desc = "Close window", noremap = true, silent = true })
map.set('n', '<leader>wh', '<C-w>h', { desc = "Move left",    noremap = true, silent = true })
map.set('n', '<leader>wl', '<C-w>l', { desc = "Move right",   noremap = true, silent = true })
map.set('n', '<leader>wj', '<C-w>j', { desc = "Move down",    noremap = true, silent = true })
map.set('n', '<leader>wk', '<C-w>k', { desc = "Move up",      noremap = true, silent = true })

-- Bufferline
map.set("n", "<Tab>", ":BufferLineCycleNext<CR>", { desc = "Prev buffer",  noremap = true, silent = true })
map.set("n", "<S-Tab>", ":BufferLineCyclePrev<CR>", { desc = "Prev buffer",  noremap = true, silent = true })
map.set("n", "<leader>tn", ":enew<CR>",             { desc = "New buffer",   noremap = true, silent = true })
map.set("n", "<leader>tc", ":bdelete<CR>",          { desc = "Close buffer", noremap = true, silent = true })
map.set("n", "<leader>tp", ":BufferLinePick<CR>",   { desc = "Pick buffer",  noremap = true, silent = true })


-- Telescope
local builtin = require('telescope.builtin')
map.set('n', '<leader>ff', builtin.find_files, { desc = "Find files", noremap = true, silent = true })
map.set('n', '<leader>fs', function()
  builtin.grep_string({ search = vim.fn.input("Grep > ") })
end, { desc = "Search string", noremap = true, silent = true }) 

-- Nvim-Tree
map.set('n', '<leader>e', ':NvimTreeFindFileToggle<CR>', { desc = "Toggle file explorer", noremap = true, silent = true })

-- Undo-Tree 
map.set('n', '<leader>u', ':UndotreeToggle<CR>', { desc = "Toggle Undotree", noremap = true, silent = true })

--map.set('v', '<leader>y', '"+y')
--map.set('n', '<leader>p', '"+p')
