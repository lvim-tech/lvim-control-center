local config = require("lvim-control-center.config")
local highlight = require("lvim-control-center.ui.highlight")
local db = require("lvim-control-center.persistence.db")
local utils = require("lvim-control-center.utils")
local commands = require("lvim-control-center.commands")

local M = {}

function M.setup(user_config)
	if user_config ~= nil then
		utils.merge(config, user_config)
	end
	db.init(config.save)
	highlight.apply_highlights()
	commands.init()
end

return M
