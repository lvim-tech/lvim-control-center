-- lvim-control-center.config: the live configuration table.
-- Holds the defaults; setup() deep-merges user overrides into it IN PLACE, so every
-- require("lvim-control-center.config") reader sees the effective values.
--
-- The internal fields (groups, save, title, title_pos) are consumed by the plugin itself;
-- popup_global is passed verbatim to require("lvim-utils.ui").new(). The panel's SIZE is NOT
-- set here — it comes from the shared lvim-utils geometry (config.ui.size.float, edited via
-- :LvimUtils / the "Utils" tab), so the panel tracks those settings.
--
---@module "lvim-control-center.config"

---@class LvimControlCenterSetting
---@field name       string                         Unique identifier used for persistence
---@field type       "bool"|"int"|"float"|"string"|"select"|"action"|"spacer"
---@field label?     string                         Display name (falls back to name)
---@field desc?      string                         Alternative display name (label fallback when no `label`)
---@field default?   any                            Default value applied when no saved value exists
---@field get?       fun(): any                     Read the current live value
---@field set?       fun(value: any, is_load: boolean, bufnr?: integer)  Apply a new value
---@field run?       fun(bufnr: integer)            Callback for action rows
---@field options?   any[]                          Available choices for select rows
---@field icon?      string                         Per-row icon override
---@field top?       any                            Extra metadata forwarded to lvim-utils
---@field bottom?    any                            Extra metadata forwarded to lvim-utils
---@field break_load? boolean                       Skip applying this setting on startup
---@field enabled?   fun(): boolean                 When it returns false the row is hidden (evaluated on open)
---@field disabled?  boolean|fun(value: any): boolean  Render the row dimmed + struck through (value unchanged); evaluated live, so it can track a parent toggle
---@field validate?  fun(value: any): boolean       Reject a changed value when it returns false (not applied/persisted)

---@class LvimControlCenterGroup
---@field name      string        Unique group identifier
---@field label?    string        Display name shown on the tab (falls back to name)
---@field icon?     string        Tab icon (trailing whitespace is stripped automatically)
---@field settings  LvimControlCenterSetting[]
---@field menu?     boolean       Force MENU vs FORM layout; nil = auto (menu when the group has no value rows)

---@class LvimControlCenterConfig
---@field groups       LvimControlCenterGroup[]  Registered setting groups
---@field save         string      Directory used for the SQLite database
---@field title        string      Window title shown in the header
---@field title_pos    "center"|"left"|"right"  Title alignment in the panel's title row
---@field popup_global table       Passed verbatim to lvim-utils.ui.new()

---@type LvimControlCenterConfig
local M = {
    -- ── internal ──────────────────────────────────────────────────────────
    groups = {},
    save = "~/.local/share/nvim/lvim-control-center",
    title = "LVIM CONTROL CENTER",
    -- Title alignment in the panel's title row: "center" (default here) | "left" | "right".
    title_pos = "center",

    -- ── lvim-utils ui instance config ────────────────────────────────────
    popup_global = {
        position = "editor",
        -- SIZE is intentionally omitted: it comes from the shared lvim-utils geometry (config.ui.size.float,
        -- edited via :LvimUtils / the "Utils" tab). ui.new() now applies the rest of this table as per-open
        -- defaults, so setting width/height here would override that shared geometry — leave it out.
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
            action = "",
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
        -- Override via setup({ popup_global = { highlights = { LvimUiTitle = "MyGroup" } } }).
        highlights = {},
    },
}

-- Expand the tilde in the save path so all downstream code receives an
-- absolute filesystem path rather than a shell-relative one.
if M.save then
    M.save = vim.fn.expand(M.save)
end

return M
