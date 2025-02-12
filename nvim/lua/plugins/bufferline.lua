return {
    {'akinsho/bufferline.nvim', version = "*", dependencies = 'nvim-tree/nvim-web-devicons'},
    vim.keymap.set("n", "<leader>n", ":bn<cr>"),
    vim.keymap.set("n", "<leader>p", ":bp<cr>"),
    vim.keymap.set("n", "<leader>x", ":bd<cr>"),
}
