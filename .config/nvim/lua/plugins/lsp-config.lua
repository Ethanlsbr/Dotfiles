return {
    {
    "williamboman/mason.nvim",
    lazy = false,
    config = function()
        require("mason").setup()
    end,
    },
    {
    "williamboman/mason-lspconfig.nvim",
    config = function()
        require("mason-lspconfig").setup({
            ensure_installed = { "lua_ls", "clangd"}
        })
        end
    },
    {
        "neovim/nvim-lspconfig",
        config = function()
            local lspconfig = require("lspconfig")
            local capabilities = require('cmp_nvim_lsp').default_capabilities()
            capabilities.textDocument.completion.completionItem.snippetSupport = false
            lspconfig.lua_ls.setup({})
            lspconfig.clangd.setup({})
            lspconfig.html.setup({})
            vim.keymap.set('n', 'K', vim.lsp.buf.hover, {})
            vim.keymap.set("n", "<leader>gd", vim.lsp.buf.definition, {})
            vim.keymap.set("n", "<leader>gr", vim.lsp.buf.references, {})
            vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, {})
        end
    },
}
