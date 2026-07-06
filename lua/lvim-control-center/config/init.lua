-- lvim-control-center.config: the default configuration TEMPLATE.
--
-- Multi-instance: there is no single live config table any more. `M.defaults()` returns a
-- FRESH table each call, and `instance.new(opts)` deep-merges the user opts into its own
-- copy — so every instance owns its config and two instances never share state. Readers hold
-- `instance.config`, not a module require.
--
-- The internal fields (command, groups, save, title, title_icon, title_pos) are consumed by
-- the plugin itself; popup_global is passed verbatim to require("lvim-ui").new(). The panel's
-- SIZE is NOT set here — it comes from the CENTRAL geometry authority
-- `lvim-utils.config.dock.geometry.float` (resolved via `lvim-utils.dock.slot` inside the surface), so
-- the panel tracks that shared geometry.
--
---@module "lvim-control-center.config"

---@class LvimControlCenterSetting
---@field name       string                         Unique identifier used for persistence
---@field type       "bool"|"int"|"float"|"string"|"select"|"action"|"spacer"
---@field label?     string                         Display name (falls back to name)
---@field desc?      string                         Alternative display name (label fallback when no `label`)
---@field default?   any                            Default value applied when no saved value exists
---@field get?       fun(ctx: LvimControlCenterCtx): any                 Read the current live value
---@field set?       fun(value: any, is_load: boolean, ctx: LvimControlCenterCtx)  Apply a new value
---@field run?       fun(bufnr: integer)            Callback for action rows
---@field options?   any[]                          Available choices for select rows
---@field icon?      string                         Per-row icon override
---@field top?       any                            Extra metadata forwarded to lvim-utils
---@field bottom?    any                            Extra metadata forwarded to lvim-utils
---@field break_load? boolean                       Skip applying this setting on startup
---@field enabled?   fun(): boolean                 When it returns false the row is hidden (evaluated on open)
---@field disabled?  boolean|fun(value: any): boolean  Render the row dimmed + struck through (value unchanged); evaluated live, so it can track a parent toggle
---@field validate?  fun(value: any): boolean       Reject a changed value when it returns false (not applied/persisted)

---@class LvimControlCenterCtx  Injected into every setting get/set — the instance's context.
---@field data     LvimControlCenterData  DEFAULT persistence — this instance's database
---@field file     fun(path: string): LvimControlCenterFile  A JSON-FILE store (same interface as `data`) for exceptions that persist to a file instead of the database (e.g. a project-local override)
---@field bufnr?   integer                The buffer active when the panel was opened (nil at startup restore)
---@field instance table                  The owning instance

---@class LvimControlCenterGroup
---@field name      string        Unique group identifier
---@field label?    string        Display name shown on the tab (falls back to name)
---@field icon?     string        Tab icon (trailing whitespace is stripped automatically)
---@field settings  LvimControlCenterSetting[]
---@field menu?     boolean       Force MENU vs FORM layout; nil = auto (menu when the group has no value rows)

---@class LvimControlCenterConfig
---@field command      string      REQUIRED — the unique key + user command that opens this instance (e.g. "LvimControlCenter")
---@field register_command? boolean  Register the `:<command>` user command (default true). false → the instance exists (keyed by `command`, opened via `:open()`) but no command is created — for a host that drives the panel from its OWN command
---@field subcommands? table<string, fun(...)>  Extra host subcommands on the instance's command — `:<command> <name> [args]` calls the matching function (checked BEFORE the built-in verbs). Lets a host add e.g. quick toggles without a second command
---@field groups       LvimControlCenterGroup[]  Registered setting groups
---@field save         string      Directory used for the SQLite database (derived from `command` when nil)
---@field title        string      Window title shown in the header
---@field title_icon   string      Nerd Font glyph shown before the title
---@field title_pos    "center"|"left"|"right"  Title alignment in the panel's title row
---@field on_change?   fun(name: string, value: any, instance: LvimControlCenterInstance)  Called after any value edited in the panel is applied — one central hook for telemetry / reload / side effects
---@field dock?         LvimControlCenterDock  Dock-stack integration (dock_stack + per-layout geometry overrides)
---@field popup_global table       Passed verbatim to lvim-ui.new()

---@class LvimControlCenterDock  Dock-stack integration, namespaced under `config.dock` (matches lvim-dependencies).
---@field dock_stack?  boolean     true = full dock-STACK consumer (managed / cyclable); false = geometry-only standalone open (see below)
---@field force?       { float: LvimDockGeometryOverride, area: LvimDockGeometryOverride, bottom: LvimDockGeometryOverride }  Per-layout ANCHORED geometry overrides deep-merged OVER the global `lvim-utils.config.dock.geometry.<layout>`

---@class LvimDockGeometryOverride  Anchored per-open override merged OVER the global dock geometry (empty {} = inherit)
---@field height?      number       Slot height — a screen fraction ≤ 1 or an absolute row count
---@field height_auto? boolean      true → content-fit UP TO `height`; false/absent → fixed `height`
---@field width?       number       FLOAT ONLY — slot width (fraction ≤ 1 or count); ignored for area/bottom (always full-width)
---@field width_auto?  boolean      FLOAT ONLY — content-fit UP TO `width`
---@field backdrop?    table|false  Backdrop veil override `{ enabled?, mode, dim = { amount }, darken = { amount } }` (or `false` to force OFF)
---@field auto_hide?   boolean      Auto-hide the entry when focus leaves it
---@field keep_focus?  boolean      Keep focus on the panel after open (do not return to the opener)

local M = {}

--- A FRESH default config table (a new table each call, so each instance owns its own).
---@return LvimControlCenterConfig
function M.defaults()
    return {
        -- ── internal ──────────────────────────────────────────────────────────
        command = nil, -- REQUIRED per instance; validated in instance.new()
        -- Register the `:<command>` user command. false → no command (host opens via :open()).
        register_command = true,
        -- Extra host subcommands on the command (name → fn), checked before the built-in verbs.
        subcommands = {},
        groups = {},
        -- nil → instance.new() derives stdpath("data")/lvim-control-center/<command>.
        save = nil,
        -- Optional central hook: fun(name, value, instance) after any panel edit is applied.
        on_change = nil,
        title = "LVIM CONTROL CENTER",
        -- Nerd Font glyph rendered before the title (cog). Override via new({ title_icon = "…" }).
        title_icon = "󰒓",
        -- Title alignment in the panel's title row: "center" (default here) | "left" | "right".
        title_pos = "center",

        -- ── dock-stack integration ───────────────────────────────────────────
        -- Namespaced under `dock` (matches lvim-dependencies → `config.dock.dock_stack` / `config.dock.force`).
        dock = {
            -- true = full dock-STACK consumer (managed: cyclable <Leader>n/p/x/m, :LvimDock,
            -- one-visible-per-layout, no overlap); false = geometry-only (central dock.slot size/
            -- backdrop, opens standalone, NOT in the stack).
            dock_stack = true,
            -- Per-plugin per-layout ANCHORED geometry overrides, deep-merged per field OVER the global
            -- `lvim-utils.config.dock.geometry.<layout>`; empty {} = inherit the global unchanged. Each
            -- layout may carry: height, height_auto, backdrop = { enabled, mode, dim = { amount },
            -- darken = { amount } }, auto_hide, keep_focus. FLOAT ALSO: width, width_auto. area/bottom
            -- are ALWAYS full-width — NO width/width_auto (ignored if set).
            -- NOTE: this is control-center's OWN override; it is SEPARATE from the global
            -- `lvim-utils.config.dock.geometry` that the built-in "Utils" panel edits.
            force = { float = {}, area = {}, bottom = {} },
        },

        -- ── lvim-ui ui instance config ───────────────────────────────────────
        popup_global = {
            position = "editor",
            -- SIZE is intentionally omitted: it comes from the CENTRAL geometry authority
            -- (`lvim-utils.config.dock.geometry.float` via `lvim-utils.dock.slot`). ui.new() applies the rest of
            -- this table as per-open defaults, so setting width/height here would override that — leave it out.
            max_items = 15,
            filetype = "lvim-utils-ui",
            close_keys = { "q", "<Esc>" },
            markview = false,

            icons = {
                bool_on = "󰄬",
                bool_off = "󰍴",
                select = "󰘮",
                number = "󰎠",
                string = "󰬴",
                action = "",
                -- 3 leading spaces so the separator line begins at the same column as a normal
                -- row's text (indent + 1-cell icon + 2), not one column further in.
                spacer = "   ──────",
                multi_selected = "󰄬",
                multi_empty = "󰍴",
                current = "➤",
            },

            labels = {
                navigate = "navigate",
                confirm = "confirm",
                cancel = "cancel",
                close = "close",
                toggle = "toggle",
                cycle = "cycle",
                edit = "edit",
                execute = "execute",
                tabs = "tabs",
            },

            keys = {
                down = "j",
                up = "k",
                confirm = "<CR>",
                cancel = "<Esc>",
                close = "q",

                tabs = {
                    next = "l",
                    prev = "h",
                },

                select = {
                    confirm = "<CR>",
                    cancel = "<Esc>",
                },

                multiselect = {
                    toggle = "<Space>",
                    confirm = "<CR>",
                    cancel = "<Esc>",
                },

                list = {
                    next_option = "<Tab>",
                    prev_option = "<BS>",
                },
            },

            -- Empty by default — uses lvim-utils global LvimUi* groups.
            -- Override via new({ popup_global = { highlights = { LvimUiTitle = "MyGroup" } } }).
            highlights = {},
        },
    }
end

return M
