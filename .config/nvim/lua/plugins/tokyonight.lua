return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("tokyonight").setup({
        style = "moon", -- "storm", "night", "moon", "day"
        transparent = true, -- Active la transparence
        terminal_colors = true, -- Applique les couleurs au terminal intégré
        styles = {
          sidebars = "transparent",
          floats = "transparent",
        },
      })

      -- Appliquer le thème
      vim.cmd("colorscheme tokyonight")

      -- Supprimer le fond de l'interface utilisateur
      vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
      vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
    end,
  },
}

