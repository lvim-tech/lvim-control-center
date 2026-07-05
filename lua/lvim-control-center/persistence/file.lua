-- lvim-control-center.persistence.file: a JSON-file-backed store with the SAME interface as the
-- database-backed `data` object (save / load / export_all / import_all / clear). It lets a setting
-- persist to a plain file INSTEAD of the instance's database — reached from any get/set via
-- `ctx.file(path)`. The DEFAULT persistence stays the database (`ctx.data`); a file is for the
-- exceptions where a value belongs somewhere else — e.g. a project-local, git-committable override
-- (lvim-linguistics' `.lvim_linguistics.json`) rather than a global DB row.
--
-- Values round-trip through `vim.json` (numbers / booleans / strings / nested tables). Every
-- operation is a read-modify-write on the file, so two settings writing the same path stay
-- consistent (they each re-read first). Bind results are memoised per normalised path.
--
---@module "lvim-control-center.persistence.file"

local M = {}

---@class LvimControlCenterFile  Persistence bound to one JSON file (same interface as LvimControlCenterData).
---@field path string
local File = {}
File.__index = File

-- One File per normalised path. Ops are stateless (re-read each time), so sharing is safe + cheap.
---@type table<string, LvimControlCenterFile>
local cache = {}

--- Bind a persistence store to the JSON file at `path` (created on first write). Same shape as
--- `data.bind` so a setting can use `ctx.file(path)` wherever it would use `ctx.data`.
---@param path string
---@return LvimControlCenterFile
function M.bind(path)
    assert(type(path) == "string" and path ~= "", "lvim-control-center: file store requires a path")
    path = vim.fs.normalize(path)
    if cache[path] then
        return cache[path]
    end
    local self = setmetatable({ path = path }, File)
    cache[path] = self
    return self
end

--- Read the whole file into a table (empty when missing / unreadable / not an object).
---@return table<string, any>
function File:read()
    local fd = io.open(self.path, "r")
    if not fd then
        return {}
    end
    local content = fd:read("*a")
    fd:close()
    local ok, decoded = pcall(vim.json.decode, content or "")
    return (ok and type(decoded) == "table") and decoded or {}
end

--- Write the whole table back to the file (creating the directory).
---@param tbl table<string, any>
---@return boolean  true on success
function File:write(tbl)
    pcall(vim.fn.mkdir, vim.fn.fnamemodify(self.path, ":h"), "p")
    local fd = io.open(self.path, "w")
    if not fd then
        return false
    end
    fd:write(vim.json.encode(tbl))
    fd:close()
    return true
end

--- Persist a value under `name`.
---@param name string
---@param value any
---@return boolean
function File:save(name, value)
    local tbl = self:read()
    tbl[name] = value
    return self:write(tbl)
end

--- Read a persisted value, or nil when absent.
---@param name string
---@return any
function File:load(name)
    local v = self:read()[name]
    if v == nil then
        return nil
    end
    return v
end

--- The whole `name → value` map.
---@return table<string, any>
function File:export_all()
    return self:read()
end

--- Merge a `name → value` map into the file. Returns the count written.
---@param map table<string, any>
---@return integer
function File:import_all(map)
    local tbl = self:read()
    local n = 0
    for k, v in pairs(map or {}) do
        tbl[k] = v
        n = n + 1
    end
    self:write(tbl)
    return n
end

--- Delete a key.
---@param name string
---@return boolean
function File:clear(name)
    local tbl = self:read()
    if tbl[name] ~= nil then
        tbl[name] = nil
        return self:write(tbl)
    end
    return true
end

return M
