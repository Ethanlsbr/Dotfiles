return {
    "catppuccin/nvim",
    lazy = false,
    name = "catppuccin",
    priority = 1000,
    config = function()
        require("catppuccin").setup {
         flavour = 'frappe',
         transparent_background = true,
         integrations = {
            bufferline = true,
         },
         term_colors = true,
         dim_inactive = {
             percentage = 0.15,
         }
        }
        vim.cmd.colorscheme "catppuccin"
    end
}
