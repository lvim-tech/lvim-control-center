-- lua/lvim-control-center/ui/init.lua
-- Bridges the control-center config to a dedicated lvim-utils UI instance.
--
-- The instance is created lazily on first open so that setup() can deep-merge
-- user overrides (including popup.highlights) before the instance is built.

local config = require("lvim-control-center.config")
local data   = require("lvim-control-center.persistence.data")

-- Lazy UI instance — nil until the first open.
local _instance = nil

local function get_ui()
	if _instance then return _instance end
	local ok, mod = pcall(require, "lvim-utils.ui")
	if not ok then return nil end
	_instance = mod.new(config.popup_global)
	return _instance
end

local M = {}

-- True while the control-center popup is visible; prevents duplicate opens.
local _is_open = false

-- ─── helpers ──────────────────────────────────────────────────────────────────

--- Resolve the current live value for a setting.
--- Priority: setting.get() → persisted DB value → setting.default.
--- Action rows carry no value and always return nil.
---@param setting LccSetting
---@return any
local function load_value(setting)
	if setting.type == "action" then
		return nil
	end
	local value
	if setting.get then
		pcall(function()
			value = setting.get()
		end)
	end
	if value == nil then
		value = data.load(setting.name)
	end
	if value == nil then
		value = setting.default
	end
	return value
end

--- Convert a LccSetting into the row format expected by lvim-utils tabs.
--- For action rows the run callback is wrapped so it receives the buffer that
--- was active before the popup was opened.
---@param setting     LccSetting
---@param origin_bufnr integer  Buffer that was current when the popup was opened
---@return table  Row table compatible with lvim-utils UiRow
local function setting_to_row(setting, origin_bufnr)
	local row = {
		type    = setting.type,
		name    = setting.name,
		label   = setting.label or setting.desc or setting.name,
		value   = load_value(setting),
		default = setting.default,
		options = setting.options,
		top     = setting.top,
		bottom  = setting.bottom,
		icon    = setting.icon,
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

--- Open the control-center popup.
--- Does nothing if the popup is already visible.
---@param tab_selector string|integer|nil  Tab to activate on open (name or 1-based index)
---@param id_or_row    string|integer|nil  Row to focus on open (name or 1-based index)
M.open = function(tab_selector, id_or_row)
	if _is_open then
		return
	end

	if not config.groups or #config.groups == 0 then
		vim.notify("No settings groups found!", vim.log.levels.ERROR)
		return
	end

	local ui = get_ui()
	if not ui then return end

	-- Remember the calling buffer so action callbacks can reference it.
	local origin_bufnr = vim.api.nvim_get_current_buf()

	-- Build one tab per group, converting each setting into a lvim-utils row.
	---@type table[]
	local tabs = {}
	for _, group in ipairs(config.groups) do
		local rows = {}
		for _, setting in ipairs(group.settings or {}) do
			table.insert(rows, setting_to_row(setting, origin_bufnr))
		end
		-- Strip any trailing whitespace that may have been appended to the icon.
		local raw_icon = ((group.icon or ""):match("^(.-)%s*$"))
		table.insert(tabs, {
			icon  = raw_icon ~= "" and raw_icon or nil,
			label = group.label or group.name,
			rows  = rows,
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
		if not setting then return end
		if setting.set then
			pcall(setting.set, row.value, false, origin_bufnr)
		else
			data.save(row.name, row.value)
		end
	end

	_is_open = true
	ui.tabs({
		title        = config.title,
		tabs         = tabs,
		tab_selector = tab_selector,
		initial_row  = id_or_row,
		on_change    = on_change,
		callback     = function() _is_open = false end,
	})
end

return M
