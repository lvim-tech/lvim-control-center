local ui = require("lvim-control-center.ui")
local data = require("lvim-control-center.persistence.data")

local M = {}

M.init = function()
	vim.api.nvim_create_user_command("LvimControlCenter", function()
		ui.open()
	end, { desc = "Open LVIM Control Center" })
	vim.api.nvim_create_autocmd("ColorScheme", {
		pattern = "*",
		callback = function()
			require("lvim-control-center.ui.highlight").apply_highlights()
		end,
	})
	data.apply_saved_settings()
end

return M
