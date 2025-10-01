local ui = require("lvim-control-center.ui")
local highlight = require("lvim-control-center.ui.highlight")
local data = require("lvim-control-center.persistence.data")

local M = {}

M.init = function()
	vim.api.nvim_create_user_command("LvimControlCenter", function(opts)
		local tab = opts.fargs[1]
		local id_or_row = opts.fargs[2]
		ui.open(tab, id_or_row)
	end, {
		desc = "Open LVIM Control Center",
		nargs = "*",
	})
	vim.api.nvim_create_autocmd("ColorScheme", {
		pattern = "*",
		callback = function()
			highlight.apply_highlights()
		end,
	})
	data.apply_saved_settings()
end

return M
