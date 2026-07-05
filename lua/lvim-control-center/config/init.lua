-- lvim-control-center.config: the default configuration TEMPLATE.
--
-- Multi-instance: there is no single live config table any more. `M.defaults()` returns a
-- FRESH table each call, and `instance.new(opts)` deep-merges the user opts into its own
-- copy — so every instance owns its config and two instances never share state. Readers hold
-- `instance.config`, not a module require.
--
-- The internal fields (command, groups, save, title, title_icon, title_pos) are consumed by
-- the plugin itself; popup_global is passed verbatim to require("lvim-ui").new(). The panel's
-- SIZE is NOT set here — it comes from the shared lvim-ui geometry (config.ui.size.float), so
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
---@field command      string      REQUIRED — the unique user command that opens this instance (e.g. "LvimControlCenter")
---@field groups       LvimControlCenterGroup[]  Registered setting groups
---@field save         string      Directory used for the SQLite database (derived from `command` when nil)
---@field title        string      Window title shown in the header
---@field title_icon   string      Nerd Font glyph shown before the title
---@field title_pos    "center"|"left"|"right"  Title alignment in the panel's title row
---@field on_change?   fun(name: string, value: any, instance: LvimControlCenterInstance)  Called after any value edited in the panel is applied — one central hook for telemetry / reload / side effects
---@field popup_global table       Passed verbatim to lvim-ui.new()

local M = {}

--- A FRESH default config table (a new table each call, so each instance owns its own).
---@return LvimControlCenterConfig
function M.defaults()
    return {
        -- ── internal ──────────────────────────────────────────────────────────
        command = nil, -- REQUIRED per instance; validated in instance.new()
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

        -- ── lvim-ui ui instance config ───────────────────────────────────────
        popup_global = {
            position = "editor",
            -- SIZE is intentionally omitted: it comes from the shared lvim-ui geometry (config.ui.size.float).
            -- ui.new() applies the rest of this table as per-open defaults, so setting width/height here would
            -- override that shared geometry — leave it out.
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
