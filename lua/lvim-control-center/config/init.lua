-- lua/lvim-control-center/config/init.lua
-- Default configuration for lvim-control-center.
-- Highlight defaults are sourced from config/highlights.lua (lvim-utils.colors palette).
--
-- Fields marked "internal" are consumed by the control center itself and are
-- NOT forwarded to the lvim-utils UI instance (see ui/init.lua).
-- All other fields are passed verbatim to require("lvim-utils.ui").new() and
-- must therefore match the lvim-utils UiInstanceCfg contract.

---@class LccIcons
---@field bool_on        string  Icon for a truthy boolean value
---@field bool_off       string  Icon for a falsy boolean value
---@field select         string  Icon for select-type settings
---@field number         string  Icon for integer settings
---@field string         string  Icon for string settings
---@field action         string  Icon for action rows
---@field spacer         string  Icon / prefix for spacer rows
---@field multi_selected string  Checkbox icon — item selected
---@field multi_empty    string  Checkbox icon — item not selected
---@field current        string  Cursor indicator for the active row

---@class LccLabels
---@field navigate string
---@field confirm  string
---@field cancel   string
---@field close    string
---@field toggle   string
---@field cycle    string
---@field edit     string
---@field execute  string
---@field tabs     string

---@class LccKeysTabs
---@field next string  Switch to the next tab
---@field prev string  Switch to the previous tab

---@class LccKeysSelect
---@field confirm string
---@field cancel  string

---@class LccKeysMultiselect
---@field toggle  string
---@field confirm string
---@field cancel  string

---@class LccKeysList
---@field next_option string  Cycle forward through options
---@field prev_option string  Cycle backward through options

---@class LccKeys
---@field down        string
---@field up          string
---@field confirm     string
---@field cancel      string
---@field close       string
---@field tabs        LccKeysTabs
---@field select      LccKeysSelect
---@field multiselect LccKeysMultiselect
---@field list        LccKeysList

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
---@field groups     LccGroup[]   -- INTERNAL: registered setting groups
---@field save       string       -- INTERNAL: directory used for the SQLite database
---@field title      string       -- INTERNAL: window title shown in the header
---@field border     string|string[]  8-element border spec or named style
---@field position   "editor"|"win"|"cursor"
---@field max_items  integer      Maximum visible rows before the list scrolls
---@field max_height number       Maximum window height as a fraction of &lines (0–1)
---@field width      number|"auto"  Window width — fraction of &columns (0–1) or "auto"
---@field height     number|"auto"  Window height — fraction of &lines   (0–1) or "auto"
---@field filetype   string       Filetype set on the floating buffer
---@field close_keys string[]     Keys that unconditionally close the popup
---@field markview   boolean      Enable markview rendering inside the popup (requires markview.nvim)
---@field icons      LccIcons
---@field labels     LccLabels
---@field keys       LccKeys
---@field highlights table<string, table>  Per-instance LvimUi* highlight overrides

local _hl_mod = require("lvim-control-center.config.highlights")

local function build_highlights()
	local h = _hl_mod.build()
	return {
		LvimUiNormal           = h.LvimCcNormal,
		LvimUiBorder           = h.LvimCcBorder,
		LvimUiTitle            = h.LvimCcTitle,
		LvimUiSeparator        = h.LvimCcSeparator,
		LvimUiFooter           = h.LvimCcFooter,
		LvimUiFooterKey        = h.LvimCcFooterKey,
		LvimUiTabActive        = h.LvimCcTabActive,
		LvimUiTabInactive      = h.LvimCcTabInactive,
		LvimUiTabIconActive    = h.LvimCcTabIconActive,
		LvimUiTabIconInactive  = h.LvimCcTabIconInactive,
		LvimUiTabTextActive    = h.LvimCcTabTextActive,
		LvimUiTabTextInactive  = h.LvimCcTabTextInactive,
		LvimUiCursorLine       = h.LvimCcCursorLine,
		LvimUiItemIconActive   = h.LvimCcItemIconActive,
		LvimUiItemIconInactive = h.LvimCcItemIconInactive,
		LvimUiItemTextActive   = h.LvimCcItemTextActive,
		LvimUiItemTextInactive = h.LvimCcItemTextInactive,
		LvimUiSpacer           = h.LvimCcSpacer,
	}
end

---@type LccConfig
local M = {
	-- ── internal (not forwarded to lvim-utils) ────────────────────────────
	groups = {},
	save = "~/.local/share/nvim/lvim-control-center",
	title = "LVIM CONTROL CENTER",

	-- ── lvim-utils ui instance config ────────────────────────────────────
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
		action = "",
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

	-- Per-instance LvimUi* overrides — colors come from config/highlights.lua
	-- (lvim-utils.colors palette) so they stay in sync with lvim-colorscheme.
	-- Users can override any group via setup({ highlights = { LvimUiTitle = {...} } }).
	highlights = build_highlights(),
}

M.build_highlights = build_highlights

-- Expand the tilde in the save path so all downstream code receives an
-- absolute filesystem path rather than a shell-relative one.
if M.save then
	M.save = vim.fn.expand(M.save)
end

return M
