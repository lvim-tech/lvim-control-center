-- lvim-control-center.persistence.db: a thin wrapper around sqlite.lua managing one
-- "settings" table (name TEXT unique → value TEXT, type TEXT) per DATABASE HANDLE. Each
-- control-center instance opens its OWN handle (its own file), so two instances never share
-- a table and setting-name collisions across instances are impossible. Every CRUD call is
-- pcall-guarded and returns false on error (or when the handle failed to open), so callers
-- never see raw sqlite errors and the plugin degrades gracefully if sqlite.lua is missing.
--
---@module "lvim-control-center.persistence.db"

local sqlite = require("sqlite.db")
local tbl = require("sqlite.tbl")

local M = {}

--- Filename of the SQLite database inside an instance's `save` directory. The directory is
--- what differs per instance (derived from its command), so the filename is constant.
M.DB_FILENAME = "lvim-control-center.db"

---@class LvimControlCenterDb  One open database handle (one instance's store).
---@field db       table   The sqlite.lua database object
---@field settings table   The "settings" table handle
local Handle = {}
Handle.__index = Handle

-- ─── lifecycle ────────────────────────────────────────────────────────────────

--- Open (or create) a database under `save_dir` and ensure the settings table exists.
--- ALWAYS returns a handle; on failure the handle is closed (`:is_open()` false) and every
--- CRUD call degrades to false — so callers never have to nil-check the handle itself.
---@param save_dir? string  Directory that will contain the database file.
---                         Defaults to stdpath("data")/lvim-control-center.
---@return LvimControlCenterDb  The handle (open on success, closed on failure)
function M.open(save_dir)
    save_dir = save_dir or (vim.fn.stdpath("data") .. "/lvim-control-center")
    local db_full_path = save_dir .. "/" .. M.DB_FILENAME
    local self = setmetatable({}, Handle)

    -- Create the storage directory when it doesn't exist yet.
    if vim.fn.isdirectory(save_dir) == 0 then
        if not pcall(vim.fn.mkdir, save_dir, "p") then
            return self
        end
    end

    local ok = pcall(function()
        self.db = sqlite({
            uri = db_full_path,
            opts = { foreign_keys = "ON" },
        })
        if not self.db then
            error("sqlite constructor returned nil")
        end
        -- One row per named setting; the name column is the natural primary key.
        self.settings = tbl("settings", {
            id = { "integer", primary = true, autoincrement = true },
            name = { "text", required = true, unique = true },
            value = { "text" },
            type = { "text" },
        }, self.db)
    end)

    if not ok or not self.db or not self.settings then
        self.db = nil
        self.settings = nil
    end
    return self
end

--- Whether the handle is open and usable.
---@return boolean
function Handle:is_open()
    return self.db ~= nil and self.settings ~= nil
end

--- Close the database connection. Subsequent CRUD calls return false.
---@return nil
function Handle:close()
    if self.db then
        pcall(function()
            if self.db.close then
                self.db:close()
            end
        end)
        self.db = nil
        self.settings = nil
    end
end

-- ─── CRUD ─────────────────────────────────────────────────────────────────────

--- Query rows from the settings table.
---@param conditions table|nil  Column-value pairs used as a WHERE clause
---@param options    table|nil  Additional query options forwarded to sqlite.tbl:get()
---@return table[]|nil|false  Matched rows, nil if none found, false on error
function Handle:find(conditions, options)
    if not self:is_open() then
        return false
    end
    local query_options = options or {}
    if conditions and next(conditions) ~= nil then
        query_options.where = conditions
    end
    local ok, result = pcall(function()
        return self.settings:get(query_options)
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
function Handle:insert(values)
    if not self:is_open() then
        return false
    end
    local ok, row_id = pcall(function()
        return self.settings:insert(values)
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
function Handle:update(conditions, values)
    if not self:is_open() then
        return false
    end
    local ok, _ = pcall(function()
        self.settings:update({ where = conditions, set = values })
    end)
    return ok
end

-- The parameter-bound upsert statement. `name` is UNIQUE, so ON CONFLICT turns the INSERT into an
-- UPDATE — one round-trip instead of find-then-insert/update. Named params (:name/:value/:type) are
-- bound by sqlite.lua, so no manual escaping. Uses RAW `db:eval`, NOT `tbl:insert`/`tbl:update`
-- (those each wrap themselves in their own BEGIN/COMMIT and would nest-error inside a transaction).
local UPSERT_SQL = "INSERT INTO settings (name, value, type) VALUES (:name, :value, :type) "
    .. "ON CONFLICT(name) DO UPDATE SET value = excluded.value, type = excluded.type"

--- Insert-or-update a settings row in one statement. sqlite.lua keeps the connection CLOSED between
--- ops (each op opens it), so a standalone upsert wraps its eval in `with_open` (open→eval→close).
--- Inside `Handle:transaction` the connection is ALREADY open, so it evals directly and does NOT
--- close it — that is what lets a batch share one connection and one BEGIN/COMMIT.
---@param name     string  Setting name (the UNIQUE key)
---@param value    string  Encoded text value
---@param type_tag string  Value type tag (int/float/bool/string/json)
---@return boolean  true on success, false on error / closed handle
function Handle:upsert(name, value, type_tag)
    if not self:is_open() then
        return false
    end
    local params = { name = name, value = value, type = type_tag }
    return pcall(function()
        if self.db:isopen() then
            self.db:eval(UPSERT_SQL, params)
        else
            self.db:with_open(function(conn)
                conn:eval(UPSERT_SQL, params)
            end)
        end
    end)
end

--- Run `fn` inside a single transaction over ONE open connection (BEGIN … COMMIT), so a bulk import
--- commits ONCE instead of opening/closing + committing per row. `fn`'s writes MUST go through
--- `Handle:upsert` (which reuses the open connection), never `tbl:insert`/`tbl:update`/`tbl:remove`
--- — those open their own nested transaction and would error. `with_open` closes the connection on
--- the way out, which auto-rolls-back if COMMIT never ran (e.g. `fn` threw). Degrades to running
--- `fn` unwrapped when the handle is closed.
---@param fn fun()  The batched work (a sequence of upserts)
---@return boolean  true if the transaction committed
function Handle:transaction(fn)
    if not self:is_open() then
        pcall(fn)
        return false
    end
    return pcall(function()
        self.db:with_open(function(conn)
            conn:eval("BEGIN")
            fn()
            conn:eval("COMMIT")
        end)
    end)
end

--- Remove rows that match conditions.
---@param conditions table  Column-value pairs for the WHERE clause
---@return boolean  true on success, false on error
function Handle:remove(conditions)
    if not self:is_open() then
        return false
    end
    local ok, _ = pcall(function()
        self.settings:remove(conditions)
    end)
    return ok
end

--- Execute a raw SQL statement. Intended for migrations / administrative tasks only.
---@param sql_query string  Raw SQL to execute
---@return any|false  Query result, or false on error
function Handle:exec(sql_query)
    if not self.db then
        return false
    end
    local ok, result = pcall(function()
        return self.db:exec(sql_query)
    end)
    if not ok then
        return false
    end
    return result
end

return M
