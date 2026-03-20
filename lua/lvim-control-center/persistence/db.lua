-- lua/lvim-control-center/persistence/db.lua
-- Thin wrapper around sqlite.lua that manages a single "settings" table.
-- All public functions return false on error so callers can handle failures
-- without having to deal with raw pcall results.

local sqlite = require("sqlite.db")
local tbl = require("sqlite.tbl")

local M = {}

--- Active database connection, nil when the DB has not been initialised yet.
---@type table|nil
M.db = nil

--- Active handle for the "settings" table, nil before init().
---@type table|nil
M.settings = nil

local DB_FILENAME = "lvim-control-center.db"

-- ─── CRUD ─────────────────────────────────────────────────────────────────────

--- Query rows from the settings table.
---@param conditions table|nil  Column-value pairs used as a WHERE clause
---@param options    table|nil  Additional query options forwarded to sqlite.tbl:get()
---@return table[]|nil|false  Matched rows, nil if none found, false on error
function M.find(conditions, options)
	if not M.db or not M.settings then
		return false
	end
	local query_options = options or {}
	if conditions and next(conditions) ~= nil then
		query_options.where = conditions
	end
	local ok, result = pcall(function()
		return M.settings:get(query_options)
	end)
	if not ok then
		return false
	end
	if result == nil or (type(result) == "table" and not next(result)) then
		return nil
	end
	return result
end

--- Insert a new row into the settings table.
---@param values table  Column-value pairs for the new row
---@return integer|false  The new row ID, or false on error
function M.insert(values)
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

--- Update existing rows that match conditions.
---@param conditions table  Column-value pairs for the WHERE clause
---@param values     table  Column-value pairs to set
---@return boolean  true on success, false on error
function M.update(conditions, values)
	if not M.db or not M.settings then
		return false
	end
	local ok, _ = pcall(function()
		M.settings:update({ where = conditions, set = values })
	end)
	return ok
end

--- Remove rows that match conditions.
---@param conditions table  Column-value pairs for the WHERE clause
---@return boolean  true on success, false on error
function M.remove(conditions)
	if not M.db or not M.settings then
		return false
	end
	local ok, _ = pcall(function()
		M.settings:remove(conditions)
	end)
	return ok
end

-- ─── lifecycle ────────────────────────────────────────────────────────────────

--- Open (or create) the SQLite database and ensure the settings table exists.
--- Safe to call multiple times; subsequent calls are no-ops if already open.
---@param path? string  Directory that will contain the database file.
---                     Defaults to stdpath("data")/lvim-control-center.
---@return boolean  true on success, false if the database could not be opened
function M.init(path)
	local save_dir = path or vim.fn.stdpath("data") .. "/lvim-control-center"
	local db_full_path = save_dir .. "/" .. DB_FILENAME

	-- Create the storage directory when it doesn't exist yet.
	if vim.fn.isdirectory(save_dir) == 0 then
		local mkdir_ok, _ = pcall(vim.fn.mkdir, save_dir, "p")
		if not mkdir_ok then
			return false
		end
	end

	local ok, _ = pcall(function()
		M.db = sqlite({
			uri = db_full_path,
			opts = { foreign_keys = "ON" },
		})
		if not M.db then
			error("sqlite constructor returned nil")
		end
		-- One row per named setting; the name column is the natural primary key.
		M.settings = tbl("settings", {
			id = { "integer", primary = true, autoincrement = true },
			name = { "text", required = true, unique = true },
			value = { "text" },
			type = { "text" },
		}, M.db)
	end)

	if not ok then
		M.db = nil
		return false
	end
	return true
end

--- Close the database connection and reset the module state.
--- Subsequent calls to find/insert/update/remove will return false until
--- init() is called again.
function M.close_db_connection()
	if M.db then
		pcall(function()
			if M.db.close then
				M.db:close()
			end
		end)
		M.db = nil
	end
end

--- Execute a raw SQL statement.
--- Intended for migrations or administrative tasks only.
---@param sql_query string  Raw SQL to execute
---@return any|false  Query result, or false on error
function M.exec(sql_query)
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
