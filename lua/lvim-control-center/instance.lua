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

local api = vim.api

-- ─── dock-stack integration (lvim-utils.dock) ──────────────────────────────────
-- The panel is a consumer of the shared DOCK-STACK manager, which keys every entry by (id, LAYOUT):
-- the instance's stable `id = "lvim-control-center:<command>"` is its base identity, and the SAME id
-- opened in a DIFFERENT layout is a SEPARATE entry in that other layout's stack. So one instance can be
-- docked in float, bottom AND area SIMULTANEOUSLY — three live panels, one entry in each stack — while
-- re-opening the SAME (id, layout) RE-SHOWS the one entry (never a duplicate in that stack). That is why
-- ALL open-state is PER LAYOUT: `self._panels[layout]` (see `Instance:panel_state`), one consumer / one
-- set of windows / one dock KEY per layout. `dock.open` RETURNS the entry key; the instance STORES it and
-- passes it back to the lifecycle APIs (`parked`/`dropped`/`hide`/`close`) for THAT entry.
--
-- Routing `:open()` through `dock.open` makes the dock's one-visible-per-layout invariant apply: opening the
-- panel PARKS whatever other consumer (a picker, a terminal, another panel) is visible in the SAME layout,
-- so the panel can never visually OVERLAP one. It also joins the dock's `<Leader>n`/`<Leader>p` cycle, the
-- `<Leader>x` kill, the `<Leader>m` menu and `:LvimDock`. Semantics = PARK & REMEMBER: `hide` closes the
-- panel window but keeps the instance + its persisted state, so `show` rebuilds it (the panel is materialised
-- fresh from config + the SQLite store on every open, so "state" is simply the instance staying alive); a
-- self-dismiss (its own `q`/`<Esc>`) parks that layout's entry (stays cyclable); `<Leader>x` (`close`) drops
-- it from the stack. When the dock is unavailable (an older lvim-utils) the panel opens directly, un-managed.
--
-- This plugin is the REFERENCE per-(id, layout) consumer — the other dock consumers copy this shape.

---@type table|false|nil  cached lvim-utils.dock module (nil = unprobed, false = probed & absent)
local dock_mod = nil
--- The dock-stack manager, or nil when unavailable — then the panel opens directly, un-managed.
---@return table?
local function get_dock()
    if dock_mod == nil then
        local ok, m = pcall(require, "lvim-utils.dock")
        dock_mod = ok and m or false
    end
    return dock_mod or nil
end

local M = {}

--- Registry of live instances by command name (for :checkhealth and duplicate detection).
---@type table<string, table>
M._instances = {}

--- Per-LAYOUT panel state. Because the dock keys every entry by (id, layout), ONE instance can be docked
--- in float, bottom AND area at once — three live panels, one entry in each stack — so every piece of
--- open-state is PER LAYOUT, kept in `self._panels[layout]` (lazily created by `Instance:panel_state`).
--- A flat `self._panel` would orphan the first window the moment the panel is opened in a second layout.
---@class LvimControlCenterPanelState
---@field is_open boolean|nil  This layout's panel is currently visible
---@field panel   table|nil    Live panel handle from ui.tabs while open (nil when closed) — used to tear it down
---@field wins    integer[]|nil  Windows this layout's open created (container + tab bar + content + footer) — the dock reads them for its leader owner / is_current
---@field focus_win integer|nil  This layout's content panel window (the dock `focus` target)
---@field consumer table|nil    Memoised LvimDockConsumer handle for THIS layout (`id` = base identity, `layout` fixed)
---@field dock_open { tab: string|integer|nil, layout: string, row: string|integer|nil }|nil  Pending open params the consumer's `show` replays
---@field key     string|nil    The dock ENTRY KEY (id, layout) returned by `dock.open` — passed back to the lifecycle APIs
---@field dock_alive boolean|nil  This entry is live/parked (true) vs killed by `<Leader>x` (false) — drives is_alive
---@field dock_teardown boolean|nil  The panel is being torn down BY the dock manager (park/close), so its close callback must NOT re-notify the dock

---@class LvimControlCenterInstance
---@field config LvimControlCenterConfig
---@field db     LvimControlCenterDb
---@field data   LvimControlCenterData
---@field _ui    table|nil  Cached lvim-ui instance (the presenter factory, built lazily on first open)
---@field _panels table<string, LvimControlCenterPanelState>  Per-layout panel state (float/bottom/area, each an independent live entry)
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

    self._panels = {}
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

--- This instance's stable dock identity / dedup key. Namespaced by the (unique) command, so two
--- instances stack as two distinct dock entries.
---@return string
function Instance:dock_id()
    return "lvim-control-center:" .. self.config.command
end

--- Lazily create + return this instance's per-LAYOUT panel state slot. Every piece of open-state (the
--- live panel handle, its windows, the memoised consumer, the dock entry KEY, the alive/teardown flags)
--- lives HERE, keyed by layout — so an open in float and an open in bottom are wholly independent live
--- entries and neither orphans the other's window.
---@param layout string  "float" | "area" | "bottom"
---@return LvimControlCenterPanelState
function Instance:panel_state(layout)
    self._panels[layout] = self._panels[layout] or {}
    return self._panels[layout]
end

--- Build (once, memoised in `_panels[layout].consumer`) + return this instance's dock consumer FOR ONE
--- LAYOUT — an `LvimDockConsumer` (the lvim-utils.dock contract; a cross-plugin type, annotated `table`).
--- `id` is the UNCHANGED base identity (`dock_id()`) — layout is NOT baked into it; the dock composes the
--- (id, layout) key. Because the SAME id can be open in every layout at once, there is ONE consumer PER
--- layout, each with a fixed `layout` and each callback reading / writing `_panels[layout]`. `show` replays
--- that layout's pending open (`ui.open` in this layout); `hide` PARKS it (close the window, keep the
--- instance → restorable); `close` (`<Leader>x`) drops the entry; `is_alive` tracks whether it was killed;
--- `buffers` / `is_current` / `focus` read that layout's live windows.
---@param layout string  "float" | "area" | "bottom"
---@return table  the LvimDockConsumer handle for this layout
function Instance:dock_consumer(layout)
    local ps = self:panel_state(layout)
    if ps.consumer then
        return ps.consumer
    end
    ps.consumer = {
        id = self:dock_id(), -- base identity, UNCHANGED across layouts — the dock keys the entry by (id, layout)
        name = self.config.title or self.config.command,
        icon = self.config.title_icon, -- the cog (verified single-width nerd glyph)
        layout = layout, -- which stack THIS entry joins (fixed for this per-layout consumer)
        show = function()
            -- A dock-driven show (open / cycle-back / restore): the panel is materialised fresh from
            -- config + the persisted store. Clear the teardown flag so the rebuilt panel's close
            -- callback parks normally again; mark the entry alive.
            ps.dock_teardown = false
            ps.dock_alive = true
            local o = ps.dock_open or {}
            ui.open(self, o.tab, o.row, layout)
        end,
        hide = function()
            self:park_panel(layout) -- PARK: close the window, KEEP the instance (restorable on the stack)
        end,
        close = function()
            -- `<Leader>x` — kill THIS layout's dock entry: tear its visible panel down and drop from the
            -- stack. The instance itself stays registered (its command still opens it again), and its
            -- OTHER layouts' entries are untouched; only this (id, layout) entry is removed.
            ps.dock_alive = false
            self:park_panel(layout)
        end,
        is_alive = function()
            return ps.dock_alive == true
        end,
        focus = function()
            local w = ps.focus_win
            if w and api.nvim_win_is_valid(w) then
                pcall(api.nvim_set_current_win, w)
            end
        end,
        buffers = function()
            -- Every live panel window's buffer (container / tab bar / content / footer) — where the
            -- dock installs its buffer-local `<Leader>` owner. All belong to this layout's dock entry.
            local out = {}
            for _, w in ipairs(ps.wins or {}) do
                if api.nvim_win_is_valid(w) then
                    local b = api.nvim_win_get_buf(w)
                    if api.nvim_buf_is_valid(b) then
                        out[#out + 1] = b
                    end
                end
            end
            return out
        end,
        is_current = function()
            if not ps.is_open then
                return false
            end
            local cur = api.nvim_get_current_win()
            for _, w in ipairs(ps.wins or {}) do
                if w == cur then
                    return true
                end
            end
            return false
        end,
    }
    return ps.consumer
end

--- PARK this layout's visible panel: close its window (KEEPING the instance + its persisted state, so
--- `show` rebuilds it) while flagging the teardown as manager-driven so the panel's close callback does
--- NOT re-notify the dock. No-op when nothing is open in that layout.
---@param layout string  "float" | "area" | "bottom"
---@return nil
function Instance:park_panel(layout)
    local ps = self:panel_state(layout)
    if ps.panel and ps.is_open and ps.panel.close then
        ps.dock_teardown = true
        pcall(ps.panel.close)
    end
end

--- Called by the UI bridge when THIS layout's panel window closes (the tabs `callback`). Resets that
--- layout's open-state, then — for a USER self-dismiss (`q`/`<Esc>`, NOT a manager park/close) — PARKS
--- that entry on the dock (by its stored KEY) so it stays cyclable (`<Leader>n/p/m`) and the layout collapses.
---@param layout string  "float" | "area" | "bottom"
---@return nil
function Instance:on_panel_closed(layout)
    local ps = self:panel_state(layout)
    ps.is_open = false
    ps.panel = nil
    ps.wins = nil
    ps.focus_win = nil
    local teardown = ps.dock_teardown
    ps.dock_teardown = false
    if teardown then
        return -- the dock manager (park/close) already fixed up its bookkeeping
    end
    local d = get_dock()
    if d and ps.dock_alive and ps.key then
        d.parked(ps.key) -- self-dismiss → keep on the stack, collapse the layout, don't reveal a neighbour
    end
end

--- Open this instance's panel. With `config.dock.dock_stack = true` (the default) AND the dock present the
--- open is ROUTED THROUGH the dock stack (`dock.open` parks any other consumer visible in the layout →
--- zero overlap, and the entry joins `<Leader>n/p/x/m` + `:LvimDock`); the consumer's `show` runs the
--- real `ui.open`. With `dock.dock_stack = false` — or without the dock (an older lvim-utils) — it opens
--- STANDALONE (`ui.open`): geometry is STILL central (the panel sizes via `dock.slot(layout,
--- config.dock.force[layout])` inside the surface, so `config.dock.force` still applies), it simply does NOT join
--- the managed stack.
---@param tab?    string|integer  Tab to activate (name or 1-based index)
---@param row?    string|integer  Row to focus (name or 1-based index)
---@param layout? string          "float" (default) | "area" | "bottom"
---@return nil
function Instance:open(tab, row, layout)
    layout = layout or "float"
    local config = self.config
    local d = get_dock()
    local ps = self:panel_state(layout)
    if d and config.dock.dock_stack then
        ps.dock_open = { tab = tab, row = row, layout = layout }
        local consumer = self:dock_consumer(layout)
        -- Refresh the ANCHORED geometry override per open: `do_show` feeds it to `dock.slot(layout,
        -- consumer.slot)` for this entry's rect. Empty {} = inherit the global geometry; a populated
        -- `config.dock.force[layout]` forces this entry's size/backdrop.
        consumer.slot = config.dock.force and config.dock.force[layout] or nil
        -- STORE the returned ENTRY KEY (id, layout): the lifecycle notifications (`parked`/`dropped`)
        -- for THIS layout's entry take that key back. Re-opening the same (id, layout) returns the same
        -- key and RE-SHOWS the one entry — never a duplicate in the stack.
        ps.key = d.open(consumer)
    else
        -- Standalone: dock_stack disabled (geometry-only) OR the dock manager is unavailable. `ui.open`
        -- still sizes from the central authority + `config.dock.force[layout]`, it is just not in the stack.
        ui.open(self, tab, row, layout)
    end
end

--- Apply every persisted setting at startup — one bulk read, then each setting's set(value, true, ctx).
--- Settings with break_load = true are skipped (their restore is owned elsewhere).
---@return nil
function Instance:apply_saved_settings()
    local saved = self.data:export_all()
    local ctx = self:ctx(nil)
    for _, group in ipairs(self.config.groups or {}) do
        for _, setting in ipairs(uconfig.settings_of(group)) do
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
        for _, setting in ipairs(uconfig.settings_of(group)) do
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
    for k, v in pairs(saved) do
        if k:sub(1, #PRESET_PREFIX) ~= PRESET_PREFIX then
            out[k] = v
        end
    end
    for _, group in ipairs(self.config.groups or {}) do
        for _, setting in ipairs(uconfig.settings_of(group)) do
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
        for _, setting in ipairs(uconfig.settings_of(group)) do
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
        for _, setting in ipairs(uconfig.settings_of(group)) do
            if setting.type ~= "spacer" then
                -- A `label` may be a producer (an action naming the effect it would have right now), so the
                -- search index asks it for a string rather than concatenating the function itself.
                local label = setting.label
                if type(label) == "function" then
                    local ok, res = pcall(label)
                    label = ok and res or nil
                end
                items[#items + 1] = {
                    group = group.name,
                    name = setting.name,
                    -- "Group ➤ Setting" — ➤ (U+27A4) is the canonical lvim-tech sequence separator.
                    label = (group.label or group.name) .. " ➤ " .. (label or setting.desc or setting.name),
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
    -- The instance is going away, not parking — so tear down ALL of its live panels, one per layout it
    -- was docked in. For each: DROP its dock entry by its stored KEY (remove the leader owner + drop it
    -- from the stack WITHOUT revealing a neighbour), then tear the visible panel down (via the live
    -- ui.tabs handle) so it can't sit open over a closed database. self._ui is the presenter FACTORY (no
    -- close); the per-open handle is `ps.panel`, set by the ui bridge on a successful open. Flag the
    -- teardown so on_panel_closed doesn't re-park.
    local d = get_dock()
    for _, ps in pairs(self._panels) do
        ps.dock_alive = false
        if d and ps.key then
            pcall(d.dropped, ps.key)
        end
        if ps.panel and ps.is_open and ps.panel.close then
            ps.dock_teardown = true
            pcall(ps.panel.close)
        end
        ps.panel = nil
        ps.is_open = false
    end
    -- Delete only the command WE created. With `register_command = false` the host owns `:<command>` and
    -- drives the panel from it; deleting it here (or via the duplicate-command replace path in M.new, which
    -- calls close()) would silently remove the host's own command.
    if self.config.register_command ~= false then
        pcall(vim.api.nvim_del_user_command, self.config.command)
    end
    if self.db then
        self.db:close()
    end
    M._instances[self.config.command] = nil
end

return M
