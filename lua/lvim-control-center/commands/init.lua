local ui = require("lvim-control-center.ui")

local M = {}

M.init = function()
	vim.api.nvim_create_user_command("LvimControlCenter", function()
		ui.open()
	end, { desc = "Open LVIM Control Center" })
	vim.api.nvim_create_autocmd("User", {
		pattern = "LvimControlCenterReady",
		callback = function()
			require("lvim-control-center.persistence.data").apply_saved_settings()
		end,
	})
	vim.api.nvim_create_autocmd("ColorScheme", {
		pattern = "*",
		callback = function()
			require("lvim-control-center.ui.highlight").apply_highlights()
		end,
	})
	vim.api.nvim_exec_autocmds("User", { pattern = "LvimControlCenterReady" })
end

return M
