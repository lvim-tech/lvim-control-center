local sqlite = require("sqlite.db")
local tbl = require("sqlite.tbl")

local M = {}
M.db = nil

local DB_FILENAME = "lvim-control-center.db"

M.find = function(conditions, options)
	if not M.db or not M.settings then
		return false
	end
	local query_options = options or {}
	if conditions and next(conditions) ~= nil then
		query_options.where = conditions
	end
	local ok, result_data = pcall(function()
		return M.settings:get(query_options)
	end)
	if not ok then
		return false
	end
	if result_data == nil or (type(result_data) == "table" and not next(result_data)) then
		return nil
	end
	return result_data
end

M.insert = function(values)
	if not M.db or not M.settings then
		return false
	end
	local ok, row_id = pcall(function()
		return M.settings:insert(values)
	end)
	if not ok then
		return false
	end
	return row_id
end

M.update = function(conditions, values)
	if not M.db or not M.settings then
		return false
	end
	local ok, _ = pcall(function()
		M.settings:update({ where = conditions, set = values })
	end)
	if not ok then
		return false
	end
	return true
end

M.remove = function(conditions)
	if not M.db or not M.settings then
		return false
	end
	local ok, _ = pcall(function()
		M.settings:remove(conditions)
	end)
	if not ok then
		return false
	end
	return true
end

M.init = function(path)
	local save_dir = path or vim.fn.stdpath("data") .. "/lvim-control-center"
	local db_full_path = save_dir .. "/" .. DB_FILENAME

	if vim.fn.isdirectory(save_dir) == 0 then
		local mkdir_ok, _ = pcall(vim.fn.mkdir, save_dir, "p")
		if not mkdir_ok then
			return false
		end
	end
	local db_init_ok, _ = pcall(function()
		M.db = sqlite({
			uri = db_full_path,
			opts = {
				foreign_keys = "ON",
			},
		})
		if not M.db then
			error("sqlite constructor for M.db returned nil")
		end
		M.settings = tbl("settings", {
			id = { "integer", primary = true, autoincrement = true },
			name = { "text", required = true, unique = true },
			value = { "text" },
			type = { "text" },
		}, M.db)
	end)
	if not db_init_ok then
		M.db = nil
		return false
	end
	return true
end

M.close_db_connection = function()
	if M.db then
		local ok, _ = pcall(function()
			if M.db.close then
				M.db:close()
			end
		end)
		if ok then
			M.db = nil
		end
	end
end

M.exec = function(sql_query)
	if not M.db then
		return false
	end
	local ok, result = pcall(function()
		return M.db:exec(sql_query)
	end)
	if not ok then
		return false
	end
	return result
end

return M
