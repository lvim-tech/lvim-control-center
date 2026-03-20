-- lua/lvim-control-center/init.lua
-- Plugin entry point.  Call M.setup() once from your Neovim config to
-- initialise the database, register user commands, and apply saved settings.

local config = require("lvim-control-center.config")
local db = require("lvim-control-center.persistence.db")
local utils = require("lvim-control-center.utils")
local commands = require("lvim-control-center.commands")

local M = {}

--- Initialise the control center.
--- Must be called before any other API usage.
---
---@param user_config? table  Partial LccConfig — deep-merged into defaults. Omit or pass nil to use defaults as-is.
function M.setup(user_config)
	-- Deep-merge user overrides into the default config table.
	if user_config ~= nil then
		utils.merge(config, user_config)
	end

	-- Initialise the SQLite persistence layer.
	db.init(config.save)

	-- Optionally set up the lvim-utils cursor module for the UI filetype.
	-- Wrapped in pcall so the plugin remains functional even when lvim-utils
	-- cursor support is unavailable.
	pcall(function()
		require("lvim-utils.cursor").setup({ ft = { "lvim-utils-ui" } })
	end)

	-- Register the :LvimControlCenter user command and apply persisted settings.
	commands.init()
end

return M
