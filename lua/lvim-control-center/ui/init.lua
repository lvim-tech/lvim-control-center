-- lvim-control-center.ui: bridges ONE instance's config to a lvim-utils UI instance. Each
-- group becomes a tab; each setting becomes a lvim-utils row (a group with only action/spacer
-- rows renders as a navigable MENU, otherwise a FORM). Row values resolve get(ctx) → the
-- instance's persisted value → default; edits persist immediately (setting.set(…, ctx) or
-- ctx.data:save) through on_change, gated by an optional per-setting validate(). The lvim-ui
-- instance is cached on the control-center instance so it is built once, lazily, on first open.
--
---@module "lvim-control-center.ui"

local M = {}

--- Return the instance's cached lvim-ui instance, building it on first call.
---@param instance LvimControlCenterInstance
---@return table|nil  The lvim-ui instance, or nil when lvim-ui is unavailable
local function get_ui(instance)
    if instance._ui then
        return instance._ui
    end
    local ok, mod = pcall(require, "lvim-ui")
    if not ok then
        return nil
    end
    instance._ui = mod.new(instance.config.popup_global)
    return instance._ui
end

-- ─── helpers ──────────────────────────────────────────────────────────────────

--- Resolve the current live value for a setting.
--- Priority: setting.get(ctx) → the instance's persisted value → setting.default.
--- Action rows carry no value and always return nil.
---@param setting LvimControlCenterSetting
---@param ctx     LvimControlCenterCtx
---@param saved   table<string, any>
---@return any
local function load_value(setting, ctx, saved)
    if setting.type == "action" then
        return nil
    end
    local value
    if setting.get then
        pcall(function()
            value = setting.get(ctx)
        end)
    end
    if value == nil then
        value = saved[setting.name]
    end
    if value == nil then
        value = setting.default
    end
    return value
end

--- Convert a LccSetting into the row format expected by lvim-utils tabs.
--- For action rows the run callback is wrapped so it receives the buffer that
--- was active before the popup was opened.
---@param setting     LvimControlCenterSetting
---@param origin_bufnr integer  Buffer that was current when the popup was opened
---@param ctx         LvimControlCenterCtx
---@param saved       table<string, any>
---@return table  Row table compatible with lvim-utils UiRow
local function setting_to_row(setting, origin_bufnr, ctx, saved)
    local row = {
        type = setting.type,
        name = setting.name,
        label = setting.label or setting.desc or setting.name,
        -- Forward the setting's `desc` onto the row so lvim-utils receives it as the row's
        -- description (used as the label fallback here, and surfaced by lvim-utils where a
        -- description line is rendered) instead of it being dropped at the bridge.
        desc = setting.desc,
        value = load_value(setting, ctx, saved),
        default = setting.default,
        options = setting.options,
        top = setting.top,
        bottom = setting.bottom,
        icon = setting.icon,
        -- `disabled` (boolean or predicate) marks a setting that exists but can't apply in the
        -- current context — lvim-utils renders it dimmed + struck through without changing its
        -- value. Evaluated live at render time, so it tracks a parent toggle (e.g. relative line
        -- numbers being inert while "Show line numbers" is off).
        disabled = setting.disabled,
    }
    if setting.type == "action" and setting.run then
        local s_run = setting.run
        ---@cast s_run fun(bufnr: integer)
        row.run = function(_, _close)
            pcall(function()
                s_run(origin_bufnr)
            end)
        end
    end
    return row
end

-- ─── public API ───────────────────────────────────────────────────────────────

--- Open an instance's control-center popup. Does nothing if it is already visible.
---@param instance     LvimControlCenterInstance
---@param tab_selector string|integer|nil  Tab to activate on open (name or 1-based index)
---@param id_or_row    string|integer|nil  Row to focus on open (name or 1-based index)
---@param layout       string|nil          "float" (default) | "area" | "bottom" — where the panel docks
---@return nil
function M.open(instance, tab_selector, id_or_row, layout)
    if instance._is_open then
        return
    end

    local config = instance.config
    if not config.groups or #config.groups == 0 then
        vim.notify("No settings groups found!", vim.log.levels.ERROR)
        return
    end

    local ui = get_ui(instance)
    if not ui then
        return
    end

    -- Remember the calling buffer so action callbacks and set(ctx) can reference it.
    local origin_bufnr = vim.api.nvim_get_current_buf()
    local ctx = instance:ctx(origin_bufnr)
    local saved = instance.data:export_all()

    -- Build one tab per group, converting each setting into a lvim-utils row.
    ---@type table[]
    local tabs = {}
    for _, group in ipairs(config.groups) do
        local rows = {}
        for _, setting in ipairs(group.settings or {}) do
            -- `enabled` (when present and returning false) hides the row — used for settings
            -- that don't apply in the current context (no LSP client, a parent toggle off…).
            local hidden = false
            if setting.enabled then
                local ok, on = pcall(setting.enabled)
                hidden = ok and not on
            end
            if not hidden then
                table.insert(rows, setting_to_row(setting, origin_bufnr, ctx, saved))
            end
        end
        -- Strip any trailing whitespace that may have been appended to the icon.
        local raw_icon = ((group.icon or ""):match("^(.-)%s*$"))
        -- A group with NO value settings (only action / spacer rows — e.g. Commands, Projects) is a navigable
        -- MENU: its rows must stay a selectable BODY list. Without this, ui.tabs collapses the childless action
        -- rows into footer buttons and the tab body looks empty. A form group (bool/select/number values) stays
        -- a form. `group.menu` overrides the auto-detect when set explicitly.
        local has_value = false
        for _, setting in ipairs(group.settings or {}) do
            if setting.type ~= "action" and setting.type ~= "spacer" then
                has_value = true
                break
            end
        end
        table.insert(tabs, {
            icon = raw_icon ~= "" and raw_icon or nil,
            name = group.name,
            label = group.label or group.name,
            rows = rows,
            menu = (group.menu ~= nil) and group.menu or not has_value,
        })
    end

    -- Build a name → setting lookup table once so on_change is O(1).
    local setting_by_name = {}
    for _, group in ipairs(config.groups) do
        for _, setting in ipairs(group.settings or {}) do
            if setting.name then
                setting_by_name[setting.name] = setting
            end
        end
    end

    --- Persist or apply a changed value immediately when the user edits a row.
    ---@param row table  The modified row (lvim-utils Row shape)
    local function on_change(row)
        local setting = setting_by_name[row.name]
        if not setting then
            return
        end
        -- `validate` rejects a changed value: it is neither applied nor persisted.
        if setting.validate then
            local ok, valid = pcall(setting.validate, row.value)
            if ok and not valid then
                vim.notify(
                    "Invalid value for " .. (setting.label or setting.name),
                    vim.log.levels.WARN,
                    { title = "Control Center" }
                )
                return
            end
        end
        if setting.set then
            pcall(setting.set, row.value, false, ctx)
        else
            ctx.data:save(row.name, row.value)
        end
        -- Central per-instance hook: one place to react to any applied edit (telemetry, reload, …).
        if instance.config.on_change then
            pcall(instance.config.on_change, row.name, row.value, instance)
        end
    end

    local ok, handle = pcall(ui.tabs, {
        title = config.title,
        title_icon = config.title_icon, -- cog by default (config/init.lua); override via new({ title_icon })
        title_pos = config.title_pos, -- centred by default (config/init.lua); "left" | "center" | "right"
        layout = layout, -- "float" (default) | "area" (msgarea dock) | "bottom" — from the command subcommand
        -- No explicit width/height: the size comes from the SHARED lvim-ui geometry (config.ui.size.float),
        -- so the panel resizes with that shared geometry.
        footer_hints = true, -- live key-hint legend at the bottom (panel keys • focused-row keys)
        tabs = tabs,
        tab_selector = tab_selector,
        initial_row = id_or_row,
        on_change = on_change,
        callback = function()
            instance._is_open = false
        end,
    })
    if ok then
        instance._is_open = true
        -- Keep the panel handle so Instance:close() can tear the visible panel down before it
        -- closes the database (otherwise edits in a still-open panel hit a closed handle).
        instance._panel = handle
    else
        instance._is_open = false
        instance._panel = nil
        vim.notify("Control Center UI failed: " .. tostring(handle), vim.log.levels.ERROR, { title = "Control Center" })
    end
end

return M
