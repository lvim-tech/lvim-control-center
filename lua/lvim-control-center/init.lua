local config = require("lvim-control-center.config")
local utils = require("lvim-control-center.utils")

local M = {}

function M.setup(user_config)
	if user_config ~= nil then
		utils.merge(config, user_config)
	end
end

return M
