-- lua/lvim-control-center/commands/init.lua
-- Registers Neovim user commands and applies settings that were persisted from
-- a previous session.

local ui   = require("lvim-control-center.ui")
local data = require("lvim-control-center.persistence.data")

local M = {}

--- Register all user-facing commands and restore persisted setting values.
--- Called once during plugin setup.
function M.init()
	-- :LvimControlCenter [tab] [row]
	--   tab  — tab name or 1-based index to activate on open (optional)
	--   row  — row name or 1-based index to focus on open  (optional)
	vim.api.nvim_create_user_command("LvimControlCenter", function(opts)
		local tab       = opts.fargs[1]
		local id_or_row = opts.fargs[2]
		ui.open(tab, id_or_row)
	end, {
		desc  = "Open LVIM Control Center",
		nargs = "*",
	})

	-- Re-apply every persisted setting so that the editor state matches the
	-- values the user saved in a previous session.
	data.apply_saved_settings()
end

return M
