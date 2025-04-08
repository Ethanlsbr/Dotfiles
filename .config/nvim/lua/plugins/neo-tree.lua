return {
	"nvim-neo-tree/neo-tree.nvim",
	branch = "v3.x",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons",
		"MunifTanjim/nui.nvim",
	},
	config = function()
		vim.keymap.set("n", "<C-n>", ":Neotree filesystem reveal left<CR>", {})
	end,
    require("neo-tree").setup({
        event_handlers = {

          {
            event = "file_open_requested",
            handler = function()
              -- auto close
              -- vimc.cmd("Neotree close")
              -- OR
              require("neo-tree.command").execute({ action = "close" })
            end
          },

        }
    })
}
