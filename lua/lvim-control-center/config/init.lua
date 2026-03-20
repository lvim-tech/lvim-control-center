-- lua/lvim-control-center/config/init.lua
-- Default configuration for lvim-control-center.
--
-- Internal fields (groups, save, title) are consumed by the plugin itself.
-- popup_global is passed verbatim to require("lvim-utils.ui").new().

---@class LccSetting
---@field name       string                         Unique identifier used for persistence
---@field type       "bool"|"int"|"float"|"string"|"select"|"action"|"spacer"
---@field label?     string                         Display name (falls back to name)
---@field desc?      string                         Alternative display name
---@field default?   any                            Default value applied when no saved value exists
---@field get?       fun(): any                     Read the current live value
---@field set?       fun(value: any, is_load: boolean, bufnr?: integer)  Apply a new value
---@field run?       fun(bufnr: integer)            Callback for action rows
---@field options?   any[]                          Available choices for select rows
---@field icon?      string                         Per-row icon override
---@field top?       any                            Extra metadata forwarded to lvim-utils
---@field bottom?    any                            Extra metadata forwarded to lvim-utils
---@field break_load? boolean                       Skip applying this setting on startup

---@class LccGroup
---@field name      string        Unique group identifier
---@field label?    string        Display name shown on the tab (falls back to name)
---@field icon?     string        Tab icon (trailing whitespace is stripped automatically)
---@field settings  LccSetting[]

---@class LccConfig
---@field groups       LccGroup[]  Registered setting groups
---@field save         string      Directory used for the SQLite database
---@field title        string      Window title shown in the header
---@field popup_global table       Passed verbatim to lvim-utils.ui.new()

---@type LccConfig
local M = {
	-- ── internal ──────────────────────────────────────────────────────────
	groups = {},
	save = "~/.local/share/nvim/lvim-control-center",
	title = "LVIM CONTROL CENTER",

	-- ── lvim-utils ui instance config ────────────────────────────────────
	popup_global = {
		border = { "", "", "", " ", " ", " ", " ", " " },
		position = "editor",
		width = 0.8,
		max_width = 0.8,
		height = "auto",
		max_height = 0.8,
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
			spacer = "    ──────",
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
