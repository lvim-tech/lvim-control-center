-- lvim-control-center.instance: one self-contained control center. Every instance owns its
-- config, its OWN SQLite database (its own file), its user command, and its open-state — so
-- you can spawn as many as you like, each with different groups and a different store, with
-- zero shared global state.
--
-- `M.new(opts)` is the real API: it requires a unique `opts.command`, deep-merges the opts
-- into a fresh copy of the defaults, opens the database (deriving the path from the command
-- when `save` is omitted), registers the command, restores persisted values, and returns the
-- instance object. Each setting's get/set receives `self:ctx()` — carrying THIS instance's
-- persistence (`ctx.data`) — so a group persists to whichever instance it belongs to.
--
---@module "lvim-control-center.instance"

local uconfig = require("lvim-control-center.config")
local db = require("lvim-control-center.persistence.db")
local data = require("lvim-control-center.persistence.data")
local file = require("lvim-control-center.persistence.file")
local commands = require("lvim-control-center.commands")
local ui = require("lvim-control-center.ui")
local merge = require("lvim-utils.utils").merge

local M = {}

--- Registry of live instances by command name (for :checkhealth and duplicate detection).
---@type table<string, table>
M._instances = {}

---@class LvimControlCenterInstance
---@field config LvimControlCenterConfig
---@field db     LvimControlCenterDb
---@field data   LvimControlCenterData
---@field _is_open boolean
---@field _ui    table|nil  Cached lvim-ui instance (built lazily on first open)
local Instance = {}
Instance.__index = Instance

--- Create a new control center instance.
---@param opts LvimControlCenterConfig  Must include a unique `command`.
---@return LvimControlCenterInstance
function M.new(opts)
    opts = opts or {}
    assert(
        type(opts.command) == "string" and opts.command ~= "",
        "lvim-control-center: new() requires a unique `command` (the user command that opens this instance)"
    )
    if M._instances[opts.command] then
        vim.notify(
            ("lvim-control-center: command %q already registered — replacing the previous instance"):format(
                opts.command
            ),
            vim.log.levels.WARN,
            { title = "Control Center" }
        )
        M._instances[opts.command]:close()
    end

    local self = setmetatable({}, Instance)
    -- Own config: deep-merge opts into a FRESH defaults copy (never a shared table).
    self.config = merge(uconfig.defaults(), opts)

    -- Own database: derive the directory from the command when `save` is omitted, so every
    -- instance gets a distinct store automatically. Normalise (expands ~, resolves env vars)
    -- so sqlite receives an absolute path — vim.fs.normalize, NOT vim.fn.expand: expand() globs
    -- and returns "" for a not-yet-existing directory (a fresh instance's), which would break it.
    if not self.config.save or self.config.save == "" then
        self.config.save = vim.fn.stdpath("data") .. "/lvim-control-center/" .. self.config.command
    end
    self.config.save = vim.fs.normalize(self.config.save)

    -- db.open ALWAYS returns a handle (closed on failure), so bind directly and just warn if it
    -- could not open — CRUD then degrades to no-ops rather than crashing.
    self.db = db.open(self.config.save)
    if not self.db:is_open() then
        vim.notify(
            ("lvim-control-center: could not open database at %s (is sqlite.lua installed?)"):format(self.config.save),
            vim.log.levels.ERROR,
            { title = "Control Center" }
        )
    end
    self.data = data.bind(self.db)

    self._is_open = false
    self._ui = nil

    -- Register the instance's own `:<command>` user command — UNLESS the host opts out
    -- (`register_command = false`), e.g. when it drives the panel from its OWN command and does not
    -- want a second, redundant one. The instance is still keyed by `command` in the registry either way.
    if self.config.register_command ~= false then
        commands.register(self)
    end
    -- Register the cross-instance :LvimControlCenterList command once (idempotent), backed by the registry.
    commands.ensure_global(M._instances)
    self:apply_saved_settings()

    M._instances[self.config.command] = self
    return self
end

--- Prefix marking a stored PRESET snapshot inside the instance's own database (kept in the same
--- table as settings, but excluded from the settings map / export by this prefix).
local PRESET_PREFIX = "__cc_preset__"

--- The context handed to every setting get/set: this instance's persistence + the origin buffer.
--- `data` is the DEFAULT store (the instance's database); `file(path)` returns a JSON-file store
--- with the SAME interface, for the exceptions that persist to a file instead (e.g. a project-local
--- override) — see persistence/file.lua.
---@param bufnr? integer
---@return LvimControlCenterCtx
function Instance:ctx(bufnr)
    return {
        data = self.data,
        file = function(path)
            return file.bind(path)
        end,
        bufnr = bufnr,
        instance = self,
    }
end

--- Open this instance's panel. Delegates to the shared UI bridge.
---@param tab?    string|integer  Tab to activate (name or 1-based index)
---@param row?    string|integer  Row to focus (name or 1-based index)
---@param layout? string          "float" (default) | "area" | "bottom"
---@return nil
function Instance:open(tab, row, layout)
    ui.open(self, tab, row, layout)
end

--- Apply every persisted setting at startup — one bulk read, then each setting's set(value, true, ctx).
--- Settings with break_load = true are skipped (their restore is owned elsewhere).
---@return nil
function Instance:apply_saved_settings()
    local saved = self.data:export_all()
    local ctx = self:ctx(nil)
    for _, group in ipairs(self.config.groups or {}) do
        for _, setting in ipairs(group.settings or {}) do
            if not setting.break_load then
                local value = saved[setting.name]
                if value == nil then
                    value = setting.default
                end
                if value ~= nil and setting.set then
                    local ok, err = pcall(setting.set, value, true, ctx)
                    if not ok then
                        vim.notify(
                            ("Restore failed for %s: %s"):format(setting.name, tostring(err)),
                            vim.log.levels.WARN,
                            { title = "Control Center" }
                        )
                    end
                end
            end
        end
    end
end

--- Reset one setting (or all when `name` is nil) to its declared default: clear the persisted
--- value and re-apply the default. Returns the count reset.
---@param name? string
---@return integer
function Instance:reset(name)
    local ctx = self:ctx(nil)
    local n = 0
    for _, group in ipairs(self.config.groups or {}) do
        for _, setting in ipairs(group.settings or {}) do
            local is_value = setting.type ~= "action" and setting.type ~= "spacer"
            if is_value and (name == nil or setting.name == name) then
                self.data:clear(setting.name)
                if not setting.break_load and setting.default ~= nil and setting.set then
                    pcall(setting.set, setting.default, true, ctx)
                end
                n = n + 1
            end
        end
    end
    return n
end

--- This instance's persisted SETTINGS map (its store minus the preset snapshots, which live in
--- the same table under `PRESET_PREFIX`). Used by export and by preset_save.
---@return table<string, any>
function Instance:settings_map()
    local out = {}
    local saved = self.data:export_all()
    for k, v in pairs(self.data:export_all()) do
        if k:sub(1, #PRESET_PREFIX) ~= PRESET_PREFIX then
            out[k] = v
        end
    end
    for _, group in ipairs(self.config.groups or {}) do
        for _, setting in ipairs(group.settings or {}) do
            if
                setting.name
                and setting.type ~= "action"
                and setting.type ~= "spacer"
                and saved[setting.name] == nil
            then
                out[setting.name] = setting.default
            end
        end
    end
    return out
end

---@param map table<string, any>
---@return nil
function Instance:replace_settings(map)
    local keep = {}
    for name in pairs(map or {}) do
        keep[name] = true
    end
    for _, group in ipairs(self.config.groups or {}) do
        for _, setting in ipairs(group.settings or {}) do
            if setting.name and not keep[setting.name] then
                self.data:clear(setting.name)
            end
        end
    end
    self.data:import_all(map or {})
end

--- The default export path for this instance (namespaced by command so instances don't collide).
---@return string
function Instance:default_export_path()
    return vim.fn.stdpath("data") .. "/lvim-control-center-" .. self.config.command .. "-export.json"
end

--- Export this instance's persisted settings to a JSON file.
---@param path? string
---@return nil
function Instance:export(path)
    -- vim.fs.normalize (not vim.fn.expand): a not-yet-existing export target must survive, and
    -- expand() globs it away to "".
    path = vim.fs.normalize(path or self:default_export_path())
    local map = self:settings_map()
    local ok, encoded = pcall(vim.json.encode, map)
    ok = ok and pcall(vim.fn.writefile, { encoded }, path)
    if ok then
        vim.notify(("Exported %d settings → %s"):format(vim.tbl_count(map), path), vim.log.levels.INFO, {
            title = "Control Center",
        })
    else
        vim.notify("Export failed: " .. path, vim.log.levels.ERROR, { title = "Control Center" })
    end
end

--- Import this instance's persisted settings from a JSON file and re-apply them live.
---@param path? string
---@return nil
function Instance:import(path)
    path = vim.fs.normalize(path or self:default_export_path())
    if vim.fn.filereadable(path) == 0 then
        vim.notify("No such file: " .. path, vim.log.levels.ERROR, { title = "Control Center" })
        return
    end
    local ok, map = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"), {
        luanil = { object = true, array = true },
    })
    if not ok or type(map) ~= "table" then
        vim.notify("Invalid import file: " .. path, vim.log.levels.ERROR, { title = "Control Center" })
        return
    end
    self:replace_settings(map)
    local n = vim.tbl_count(map)
    self:apply_saved_settings()
    vim.notify(("Imported %d settings"):format(n), vim.log.levels.INFO, { title = "Control Center" })
end

--- Fuzzy-search EVERY setting across all this instance's tabs through the canonical lvim-ui
--- picker (centered + themed). Choosing one opens the panel focused on that setting's row.
---@return nil
function Instance:search()
    local items = {}
    for _, group in ipairs(self.config.groups or {}) do
        for _, setting in ipairs(group.settings or {}) do
            if setting.type ~= "spacer" then
                items[#items + 1] = {
                    group = group.name,
                    name = setting.name,
                    -- "Group ➤ Setting" — ➤ (U+27A4) is the canonical lvim-tech sequence separator.
                    label = (group.label or group.name) .. " ➤ " .. (setting.label or setting.desc or setting.name),
                }
            end
        end
    end
    if #items == 0 then
        vim.notify("No settings to search.", vim.log.levels.INFO, { title = "Control Center" })
        return
    end
    local ok, lui = pcall(require, "lvim-ui")
    if not ok then
        return
    end
    lui.select({
        title = "Search settings",
        items = items,
        callback = function(confirmed, index)
            local it = confirmed and items[index]
            if it then
                self:open(it.group, it.name)
            end
        end,
    })
end

--- Save the current settings as a named PRESET (a profile) inside this instance's own database.
---@param name string
---@return boolean  true on success
function Instance:preset_save(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    return self.data:save(PRESET_PREFIX .. name, self:settings_map()) ~= false
end

--- Load a named preset: apply its stored settings live and persist them as the current values.
---@param name string
---@return boolean  true when the preset existed and was applied
function Instance:preset_load(name)
    local map = self.data:load(PRESET_PREFIX .. name)
    if type(map) ~= "table" then
        return false
    end
    self:replace_settings(map)
    self:apply_saved_settings()
    return true
end

--- Delete a named preset.
---@param name string
---@return boolean
function Instance:preset_delete(name)
    return self.data:clear(PRESET_PREFIX .. name)
end

--- List the names of all saved presets, sorted.
---@return string[]
function Instance:preset_list()
    local names = {}
    for k in pairs(self.data:export_all()) do
        if k:sub(1, #PRESET_PREFIX) == PRESET_PREFIX then
            names[#names + 1] = k:sub(#PRESET_PREFIX + 1)
        end
    end
    table.sort(names)
    return names
end

--- Close this instance: drop its command, close its database, and remove it from the registry.
---@return nil
function Instance:close()
    if self._ui and self._is_open and self._ui.close then
        pcall(self._ui.close)
    end
    self._is_open = false
    pcall(vim.api.nvim_del_user_command, self.config.command)
    if self.db then
        self.db:close()
    end
    M._instances[self.config.command] = nil
end

return M
