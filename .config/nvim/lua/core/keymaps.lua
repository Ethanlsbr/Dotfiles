-- Set leader key
vim.g.mapleader = ' '
vim.g. maplocalleader = ' '

-- Disable the spacebar key's default behavior in Normal and Visual modes
vim.keymap.set({ 'n', 'v'}, '<Space>', '<Nop>', { silent = true })

-- For conciseness
local opts = { noremap = true, silent = true }

-- Reminder 'CR' stand for the return key
-- Save file
vim.keymap.set('n', '<C-s', '<cmd> w <CR>', opts)

-- Quit file
vim.keymap.set('n', '<C-q>', '<cmd> q <CR>', opts)

-- Resize with arrows
-- vim.keymap.set('n', '<Up>', '<cmd> resize -2 <CR>', opts)
-- vim.keymap.set('n', '<Down>', '<cmd> resize +2 <CR>', opts)
-- vim.keymap.set('n', '<Left>', '<cmd> vertical resize -2 <CR>', opts)
-- vim.keymap.set('n', '<Right>', '<cmd> vertical resize +2 <CR>', opts)

-- Buffers
vim.keymap.set('n', '<Tab>', '<cmd> bnext <CR>', opts)
vim.keymap.set('n', '<S-Tab>', '<cmd> bprevious <CR>', opts)
vim.keymap.set('n', '<leader>x', '<cmd> bdelete! <CR>', opts) -- close buffer
vim.keymap.set('n', '<leader>b', '<cmd> enew <CR>', opts) -- new buffer

-- Window management
-- vim.keymap.set('n', '<leader>v', '<C-w>v', opts)
-- vim.keymap.set('n', '<leader>h', '<C-w>s', opts)
-- vim.keymap.set('n', '<leader>se', '<C-w>=', opts)
-- vim.keymap.set('n', '<leader>xs', '<cmd> close <CR>', opts)

-- Navigate between splits
-- vim.keymap.set('n', '<C-k>', '<cmd> wincmd k <CR>', opts)
-- vim.keymap.set('n', '<C-j>', '<cmd> wincmd j <CR>', opts)
-- vim.keymap.set('n', '<C-h>', '<cmd> wincmd h <CR>', opts)
-- vim.keymap.set('n', '<C-l>', '<cmd> wincmd l <CR>', opts)

-- Open Neotree on the left side
vim.keymap.set("n", "<C-n>", "<cmd> Neotree filesystem reveal left <CR>", opts)

-- Put line in comment format
vim.keymap.set({"n", "v"}, "<C-:>", "<cmd> CommentToggle <CR>", opts)

-- Create Epitech header
vim.keymap.set("n", "<leader>eh", ":InsertHeader<CR>")

-- Erase a word
vim.keymap.set('i', '<C-BS>', '<C-W>', { noremap = true, silent = true })
