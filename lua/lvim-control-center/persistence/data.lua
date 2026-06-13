-- lua/lvim-control-center/persistence/data.lua
-- High-level persistence API.
-- Translates between Lua values and the (type, text) pairs stored in SQLite.

local db = require("lvim-control-center.persistence.db")
local config = require("lvim-control-center.config")

local M = {}

-- ─── encoding / decoding ──────────────────────────────────────────────────────

---@alias LccValueType "int"|"float"|"bool"|"string"|"json"

--- Encode a Lua value into a (type-tag, text) pair suitable for SQLite storage.
---@param value any
---@return LccValueType type_tag
---@return string       text_value
local function encode_value(value)
    if type(value) == "number" then
        if math.floor(value) ~= value then
            return "float", tostring(value)
        end
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

--- Decode a (type-tag, text) pair retrieved from SQLite back into a Lua value.
---@param val      string        Raw text value from the database
---@param val_type LccValueType  Type tag stored alongside the value
---@return any  Decoded Lua value, or nil on failure
local function decode_value(val, val_type)
    if val_type == "int" or val_type == "float" then
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

-- ─── public API ───────────────────────────────────────────────────────────────

--- Persist a setting value.
--- Inserts a new row if the setting has never been saved; updates it otherwise.
---@param param string  Setting name (primary key in the DB)
---@param value any     Value to store
---@return integer|boolean  Row ID on insert, true on update, false on error
function M.save(param, value)
    local val_type, db_value = encode_value(value)
    local existing = db.find({ name = param })
    if existing and existing[1] then
        return db.update({ name = param }, { value = db_value, type = val_type })
    else
        return db.insert({ name = param, value = db_value, type = val_type })
    end
end

--- Load a persisted setting value.
---@param param string  Setting name to look up
---@return any  The decoded value, or nil if nothing has been saved yet
function M.load(param)
    local found = db.find({ name = param })
    if found and found[1] then
        return decode_value(found[1].value, found[1].type)
    end
    return nil
end

--- Export every persisted setting as a `name → value` map.
---@return table<string, any>
function M.export_all()
    local out = {}
    local rows = db.find()
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
function M.import_all(map)
    local n = 0
    for name, value in pairs(map or {}) do
        if M.save(name, value) ~= false then
            n = n + 1
        end
    end
    return n
end

--- Delete a setting's persisted value (so it reverts to its declared default).
---@param name string
function M.clear(name)
    return db.remove({ name = name })
end

--- Reset one setting (or all when `name` is nil) to its declared default: clears the
--- persisted value and re-applies the default via `set(default, true)`. Returns the count.
---@param name? string
---@return integer
function M.reset(name)
    local n = 0
    for _, group in ipairs(config.groups or {}) do
        for _, setting in ipairs(group.settings or {}) do
            local is_value = setting.type ~= "action" and setting.type ~= "spacer"
            if is_value and (name == nil or setting.name == name) then
                M.clear(setting.name)
                if setting.default ~= nil and setting.set then
                    pcall(setting.set, setting.default, true)
                end
                n = n + 1
            end
        end
    end
    return n
end

--- Apply every persisted setting at startup.
--- Iterates all registered groups and calls each setting's set() callback with
--- the saved value (or the declared default when nothing is persisted).
--- Settings with break_load = true are skipped — they are intentionally
--- excluded from automatic restoration.
function M.apply_saved_settings()
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
