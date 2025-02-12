local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end

vim.opt.rtp:prepend(lazypath)

vim.api.nvim_set_keymap('i', '<C-BS>', '<C-W>', { noremap = true, silent = true })
vim.keymap.set("n", "<leader>y", [["+y]])
vim.keymap.set({"n", "v"}, "<C-:>", ":CommentToggle<CR>")

require("vim-options")
require("lazy").setup("plugins")

vim.diagnostic.disable()

--vim.opt.termguicolors = true
--require("bufferline").setup{}

require('nvim_comment').setup{}

require("notify").setup ({
  background_colour = "#000000"
})

if vim.g.neovide then
  vim.g.neovide_transparency = 0.2
end


-----------------------------THEME---------------------------

-----ONE DARK PRO-----
--
-- require("onedarkpro").setup({
--   options = {
--     transparency = true
--   },
--   styles = {
--     types = "NONE",
--     methods = "NONE",
--     numbers = "NONE",
--     strings = "NONE",
--     comments = "italic",
--     keywords = "bold,italic",
--     constants = "NONE",
--     functions = "italic",
--     operators = "NONE",
--     variables = "NONE",
--     parameters = "NONE",
--     conditionals = "italic",
--     virtual_text = "NONE",
--   }
-- })
--
-- vim.cmd("colorscheme onedark")



-----CATPPUCCIN-----

require("catppuccin").setup {
  transparent_background = true,
  term_colors = true,
  dim_inactive = {
      percentage = 0.15,
  }
}

vim.cmd.colorscheme "catppuccin"

-------------------------------------------------------------

vim.api.nvim_create_user_command(
  'DiagnosticsToggleVirtualText',
  function()
    local current_value = vim.diagnostic.config().virtual_text
    if current_value then
      vim.diagnostic.config({virtual_text = false})
    else
      vim.diagnostic.config({virtual_text = true})
    end
  end,
  {}
)

vim.api.nvim_set_keymap('n', '<Leader>ii', ':lua vim.cmd("DiagnosticsToggleVirtualText")<CR>', { noremap = true, silent = true })

vim.api.nvim_set_keymap('n', '<Leader>id', ':lua vim.cmd("DiagnosticsToggle")<CR>', { noremap = true, silent = true })

vim.api.nvim_create_user_command(
  'DiagnosticsToggle',
  function()
    local current_value = vim.diagnostic.is_disabled()
    if current_value then
      vim.diagnostic.enable()
    else
      vim.diagnostic.disable()
    end
  end,
  {}
)



return {
    opts = {
       --transparent_backkground = true,
    },
    config = function (_, opts)
        require('notify').setup(vim.tbl_extend('keep', {
            background_colour = "#000000"
        }, opts))
    end
}

