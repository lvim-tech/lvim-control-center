-- lvim-control-center.persistence.data: high-level persistence API BOUND to one database
-- handle. `M.bind(handle)` returns a small object (save / load / export_all / import_all /
-- clear) that reads and writes THAT instance's store — it is exactly the `ctx.data` handed
-- to every setting's get/set, so a group persists to whichever instance it is registered in
-- (it never reaches for a global module). Translates between Lua values and the (type-tag,
-- text) pairs stored in SQLite (int / float / bool / string / json).
--
---@module "lvim-control-center.persistence.data"

local M = {}

---@class LvimControlCenterData  Persistence bound to one instance's database handle.
---@field db LvimControlCenterDb
local Data = {}
Data.__index = Data

-- ─── encoding / decoding ──────────────────────────────────────────────────────

---@alias LvimControlCenterValueType "int"|"float"|"bool"|"string"|"json"

--- Encode a Lua value into a (type-tag, text) pair suitable for SQLite storage.
---@param value any
---@return LvimControlCenterValueType? type_tag
---@return string?       text_value
local function encode_value(value)
    if value == nil then
        return nil, nil
    end
    if type(value) == "number" then
        if math.floor(value) ~= value then
            return "float", ("%.17g"):format(value)
        end
        return "int", tostring(value)
    elseif type(value) == "boolean" then
        return "bool", value and "1" or "0"
    elseif type(value) == "string" then
        return "string", value
    elseif type(value) == "table" then
        local ok, json = pcall(vim.json.encode, value)
        if ok then
            return "json", json
        end
        return nil, nil
    else
        return "string", tostring(value)
    end
end

--- Decode a (type-tag, text) pair retrieved from SQLite back into a Lua value.
---@param val      string        Raw text value from the database
---@param val_type LvimControlCenterValueType  Type tag stored alongside the value
---@return any  Decoded Lua value, or nil on failure
local function decode_value(val, val_type)
    if val_type == "int" or val_type == "float" then
        return tonumber(val)
    elseif val_type == "bool" then
        return val == "1"
    elseif val_type == "json" then
        local ok, decoded = pcall(vim.json.decode, val, { luanil = { object = true, array = true } })
        if ok then
            return decoded
        end
        return nil
    else
        return val
    end
end

-- ─── construction ─────────────────────────────────────────────────────────────

--- Bind a persistence API to a database handle. The returned object is the `ctx.data`
--- passed to setting get/set callbacks.
---@param handle LvimControlCenterDb
---@return LvimControlCenterData
function M.bind(handle)
    return setmetatable({ db = handle }, Data)
end

-- ─── public API ───────────────────────────────────────────────────────────────

--- Persist a setting value into this instance's store (insert or update).
---@param param string  Setting name (primary key in the DB)
---@param value any     Value to store
---@return integer|boolean  Row ID on insert, true on update, false on error
function Data:save(param, value)
    if value == nil then
        return self:clear(param)
    end
    local val_type, db_value = encode_value(value)
    if not (val_type and db_value) then
        return false
    end
    local existing = self.db:find({ name = param })
    if existing and existing[1] then
        return self.db:update({ name = param }, { value = db_value, type = val_type })
    else
        return self.db:insert({ name = param, value = db_value, type = val_type })
    end
end

--- Load a persisted setting value from this instance's store.
---@param param string  Setting name to look up
---@return any  The decoded value, or nil if nothing has been saved yet
function Data:load(param)
    local found = self.db:find({ name = param })
    if found and found[1] then
        return decode_value(found[1].value, found[1].type)
    end
    return nil
end

--- Export every persisted setting in this instance's store as a `name → value` map.
---@return table<string, any>
function Data:export_all()
    local out = {}
    local rows = self.db:find()
    if type(rows) == "table" then
        for _, r in ipairs(rows) do
            if r.name then
                out[r.name] = decode_value(r.value, r.type)
            end
        end
    end
    return out
end

--- Import a `name → value` map, persisting each entry. Returns the count written.
---@param map table<string, any>
---@return integer
function Data:import_all(map)
    local n = 0
    for name, value in pairs(map or {}) do
        if self:save(name, value) ~= false then
            n = n + 1
        end
    end
    return n
end

--- Delete a setting's persisted value (so it reverts to its declared default).
---@param name string
---@return boolean  true on success, false on error
function Data:clear(name)
    return self.db:remove({ name = name })
end

return M
