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

-- ─── bound statements ─────────────────────────────────────────────────────────
--
-- Every CRUD call binds its values BY INDEX through sqlite.stmt (the same approach as
-- lvim-utils.store.sqlite). sqlite.lua's convenience layer (`tbl:get` / `tbl:insert` /
-- `tbl:update` / `tbl:remove`, and the named-parameter form of `stmt:bind`) inlines a WHERE
-- value as a literal and treats a string shaped like a function call (`date('now')`,
-- `client.log(1)`) as a SQL EXPRESSION spliced in unbound — such a setting could not be
-- written, and an update to such a value silently lost the row. Binding by index goes
-- straight to the C API: a value is always just a value.

--- A column name that can be spliced into SQL verbatim.
---@param name any
---@return boolean
local function is_ident(name)
    return type(name) == "string" and name:match("^[%a_][%w_]*$") ~= nil
end

--- Run `fn(conn)` on the open connection, opening one for the call when sqlite.lua has closed it
--- between operations (inside `Handle:transaction` it is already open and must stay so).
---@param db table
---@param fn fun(conn: any)
---@return boolean ok
local function with_conn(db, fn)
    return pcall(function()
        if db:isopen() then
            fn(db.conn)
        else
            db:with_open(function(c)
                fn(c.conn)
            end)
        end
    end)
end

--- `key = ?` pairs for a column→value map, in a fixed order, with the bound values.
---@param map table
---@return string[] clauses, any[] args
local function pairs_bound(map)
    local keys = {}
    for k in pairs(map or {}) do
        if not is_ident(k) then
            error("invalid column name: " .. tostring(k))
        end
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local clauses, args = {}, {}
    for _, k in ipairs(keys) do
        clauses[#clauses + 1] = k .. " = ?"
        args[#args + 1] = map[k]
    end
    return clauses, args
end

--- Bind `args` by index and step the statement (writes).
---@param conn any
---@param sql string
---@param args any[]
local function exec_bound(conn, sql, args)
    local sqlstmt = require("sqlite.stmt")
    local stmt = sqlstmt:parse(conn, sql)
    for i, v in ipairs(args) do
        if type(v) == "boolean" then
            v = v and 1 or 0
        end
        stmt:bind(i, v)
    end
    stmt:step()
    stmt:finalize()
end

--- Bind `args` by index and collect the rows (reads).
---@param conn any
---@param sql string
---@param args any[]
---@return table[]
local function query_bound(conn, sql, args)
    local sqlstmt = require("sqlite.stmt")
    local stmt = sqlstmt:parse(conn, sql)
    for i, v in ipairs(args) do
        if type(v) == "boolean" then
            v = v and 1 or 0
        end
        stmt:bind(i, v)
    end
    local rows = stmt:kvrows()
    stmt:finalize()
    return rows or {}
end

-- ─── CRUD ─────────────────────────────────────────────────────────────────────

--- Query rows from the settings table.
---@param conditions table|nil  Column-value pairs used as a WHERE clause (all must match)
---@param options    table|nil  `order_by = { asc = column }` / `{ desc = column }`, `limit = n`
---@return table[]|nil|false  Matched rows, nil if none found, false on error
function Handle:find(conditions, options)
    if not self:is_open() then
        return false
    end
    local sql = "SELECT * FROM settings"
    local clauses, args = {}, {}
    local ok_where = pcall(function()
        clauses, args = pairs_bound(conditions)
    end)
    if not ok_where then
        return false
    end
    if #clauses > 0 then
        sql = sql .. " WHERE " .. table.concat(clauses, " AND ")
    end
    options = options or {}
    if type(options.order_by) == "table" then
        local col, dir = options.order_by.asc, "ASC"
        if not col then
            col, dir = options.order_by.desc, "DESC"
        end
        if is_ident(col) then
            sql = sql .. " ORDER BY " .. col .. " " .. dir
        end
    end
    if type(options.limit) == "number" then
        sql = sql .. " LIMIT " .. math.floor(options.limit)
    end
    local rows
    local ok = with_conn(self.db, function(conn)
        rows = query_bound(conn, sql, args)
    end)
    if not ok then
        return false
    end
    if rows == nil or not next(rows) then
        return nil
    end
    return rows
end

--- Insert a new row into the settings table.
---@param values table  Column-value pairs for the new row
---@return integer|false  The new row ID, or false on error
function Handle:insert(values)
    if not self:is_open() then
        return false
    end
    local cols, args, marks = {}, {}, {}
    local ok_cols = pcall(function()
        local clauses
        clauses, args = pairs_bound(values)
        for _, c in ipairs(clauses) do
            cols[#cols + 1] = c:sub(1, -5) -- strip " = ?"
            marks[#marks + 1] = "?"
        end
    end)
    if not ok_cols or #cols == 0 then
        return false
    end
    local sql = ("INSERT INTO settings (%s) VALUES (%s)"):format(table.concat(cols, ", "), table.concat(marks, ", "))
    local rowid
    local ok = with_conn(self.db, function(conn)
        exec_bound(conn, sql, args)
        local row = query_bound(conn, "SELECT last_insert_rowid() AS id", {})[1]
        rowid = row and tonumber(row.id) or nil
    end)
    if not ok then
        return false
    end
    return rowid or false
end

--- Update existing rows that match conditions.
---@param conditions table  Column-value pairs for the WHERE clause
---@param values     table  Column-value pairs to set
---@return boolean  true on success, false on error
function Handle:update(conditions, values)
    if not self:is_open() then
        return false
    end
    local sets, set_args, wheres, where_args
    local ok_build = pcall(function()
        sets, set_args = pairs_bound(values)
        wheres, where_args = pairs_bound(conditions)
    end)
    if not ok_build or #sets == 0 then
        return false
    end
    local sql = "UPDATE settings SET " .. table.concat(sets, ", ")
    if #wheres > 0 then
        sql = sql .. " WHERE " .. table.concat(wheres, " AND ")
    end
    local args = {}
    vim.list_extend(args, set_args)
    vim.list_extend(args, where_args)
    return with_conn(self.db, function(conn)
        exec_bound(conn, sql, args)
    end)
end

-- The upsert statement. `name` is UNIQUE, so ON CONFLICT turns the INSERT into an UPDATE — one
-- round-trip instead of find-then-insert/update. Values are bound by index (see above). Uses the
-- raw connection, NOT `tbl:insert`/`tbl:update` (those each wrap themselves in their own
-- BEGIN/COMMIT and would nest-error inside a transaction).
local UPSERT_SQL = "INSERT INTO settings (name, value, type) VALUES (?, ?, ?) "
    .. "ON CONFLICT(name) DO UPDATE SET value = excluded.value, type = excluded.type"

--- Insert-or-update a settings row in one statement. sqlite.lua keeps the connection CLOSED between
--- ops (each op opens it), so a standalone upsert opens one for the call. Inside `Handle:transaction`
--- the connection is ALREADY open, so it runs directly and does NOT close it — that is what lets a
--- batch share one connection and one BEGIN/COMMIT.
---@param name     string  Setting name (the UNIQUE key)
---@param value    string  Encoded text value
---@param type_tag string  Value type tag (int/float/bool/string/json)
---@return boolean  true on success, false on error / closed handle
function Handle:upsert(name, value, type_tag)
    if not self:is_open() then
        return false
    end
    return with_conn(self.db, function(conn)
        exec_bound(conn, UPSERT_SQL, { name, value, type_tag })
    end)
end

--- Run `fn` inside a single transaction over ONE open connection (BEGIN … COMMIT), so a bulk import
--- commits ONCE instead of opening/closing + committing per row. `fn`'s writes MUST go through the
--- bound CRUD calls of this handle (which reuse the open connection), never sqlite.lua's `tbl:*`
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
---@param conditions table  Column-value pairs for the WHERE clause (all must match)
---@return boolean  true on success, false on error
function Handle:remove(conditions)
    if not self:is_open() then
        return false
    end
    local clauses, args
    local ok_build = pcall(function()
        clauses, args = pairs_bound(conditions)
    end)
    if not ok_build then
        return false
    end
    local sql = "DELETE FROM settings"
    if #clauses > 0 then
        sql = sql .. " WHERE " .. table.concat(clauses, " AND ")
    end
    return with_conn(self.db, function(conn)
        exec_bound(conn, sql, args)
    end)
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
