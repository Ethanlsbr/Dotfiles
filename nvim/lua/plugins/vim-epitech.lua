return {
    "ProudFaceOfSUiR/epitech.nvim",
    lazy = false,
    config = function ()
        require("epitech-header")
        vim.keymap.set("n", "<leader>eh", ":InsertHeader<CR>")
    end
}
