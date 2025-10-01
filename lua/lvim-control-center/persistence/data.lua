local db = require("lvim-control-center.persistence.db")
local config = require("lvim-control-center.config")

local M = {}

local function encode_value(value)
	if type(value) == "number" then
		return "int", tostring(value)
	elseif type(value) == "boolean" then
		return "bool", value and "1" or "0"
	elseif type(value) == "string" then
		return "string", value
	elseif type(value) == "table" then
		local ok, json = pcall(vim.fn.json_encode, value)
		if ok then
			return "json", json
		else
			error("Failed to encode value as JSON")
		end
	else
		return "string", tostring(value)
	end
end

local function decode_value(val, val_type)
	if val_type == "int" then
		return tonumber(val)
	elseif val_type == "bool" then
		return val == "1"
	elseif val_type == "json" then
		local ok, decoded = pcall(vim.fn.json_decode, val)
		if ok then
			return decoded
		end
		return nil
	else
		return val
	end
end

M.save = function(param, value)
	local val_type, db_value = encode_value(value)
	local existing = db.find({ name = param })
	if existing and existing[1] then
		return db.update({ name = param }, { value = db_value, type = val_type })
	else
		return db.insert({ name = param, value = db_value, type = val_type })
	end
end

M.load = function(param)
	local found = db.find({ name = param })
	if found and found[1] then
		return decode_value(found[1].value, found[1].type)
	end
	return nil
end

M.apply_saved_settings = function()
	for _, group in ipairs(config.groups or {}) do
		for _, setting in ipairs(group.settings or {}) do
			if not setting.break_load then
				local value = M.load(setting.name)
				if value == nil then
					value = setting.default
				end
				if value ~= nil and setting.set then
					setting.set(value, true)
				end
			end
		end
	end
end

return M
