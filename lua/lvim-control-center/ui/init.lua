local config = require("lvim-control-center.config")
local highlight = require("lvim-control-center.ui.highlight")
local data = require("lvim-control-center.persistence.data")

local M = {}

local function render_setting_line(setting, value)
	local label = setting.label or setting.desc or setting.name
	local t = setting.type
	if t == "bool" or t == "boolean" then
		return string.format("%s %s", value and "󰄳" or "󰄰", label)
	elseif t == "select" then
		return string.format(" %s: %s", label, value)
	else
		return string.format(" %s: %s", label, value)
	end
end

local function get_settings_lines(group)
	local lines = {}
	for _, setting in ipairs(group.settings or {}) do
		local value = data.load(setting.name)
		if value == nil and setting.default ~= nil then
			value = setting.default
		end
		local line = render_setting_line(setting, value)
		table.insert(lines, line)
	end
	return lines
end

local function set_cursor_blend(blend)
	vim.cmd("hi Cursor blend=" .. tostring(blend))
end

M.open = function(initial_tab)
	highlight.apply_highlights()

	local active_tab = initial_tab or 1
	local group_count = #config.groups
	if group_count == 0 then
		vim.notify("No settings groups found!", vim.log.levels.ERROR)
		return
	end

	local function get_win_size()
		local width = math.floor(vim.o.columns * (config.window_size and config.window_size.width or 0.6))
		local height = math.floor(vim.o.lines * (config.window_size and config.window_size.height or 0.5))
		width = math.max(width, 30)
		height = math.max(height, 8)
		return width, height
	end

	local width, height = get_win_size()
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		border = "rounded",
		style = "minimal",
		noautocmd = true,
	})
	_G.LVIM_CONTROL_CENTER_WIN = win

	vim.bo[buf].filetype = "lvim-control-center"

	vim.api.nvim_set_option_value(
		"winhighlight",
		"Normal:ConfigCenterFloat,FloatBorder:ConfigCenterBorder,Title:ConfigCenterTitle",
		{ win = win }
	)

	set_cursor_blend(100)
	local cursor_group = vim.api.nvim_create_augroup("LvimControlCenterCursorBlend", { clear = true })

	vim.api.nvim_create_autocmd({ "WinEnter", "WinLeave" }, {
		group = cursor_group,
		buffer = buf,
		callback = function()
			if vim.api.nvim_get_current_win() == win then
				set_cursor_blend(100)
			else
				_G.LVIM_CONTROL_CENTER_WIN = nil
				set_cursor_blend(0)
			end
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		buffer = buf,
		callback = function()
			_G.LVIM_CONTROL_CENTER_WIN = nil
			set_cursor_blend(0)
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = cursor_group,
		buffer = buf,
		callback = function()
			set_cursor_blend(0)
		end,
		once = true,
	})

	local active_setting_row = 1

	local function draw()
		vim.bo[buf].modifiable = true
		local lines = {}
		local tabs = {}
		local tab_ranges = {}
		local col = 0
		for i, group in ipairs(config.groups) do
			local name = " " .. (group.icon or "") .. " " .. group.name .. " "
			table.insert(tabs, name)
			local start_col = col
			local end_col = col + #name
			table.insert(tab_ranges, { active = (i == active_tab), start_col = start_col, end_col = end_col })
			col = end_col
		end
		local tabs_line = table.concat(tabs, "")
		table.insert(lines, tabs_line)
		table.insert(lines, string.rep("─", width))
		local group = config.groups[active_tab]
		local content_lines = get_settings_lines(group)
		for _, l in ipairs(content_lines) do
			table.insert(lines, l)
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

		local ns_id = vim.api.nvim_create_namespace("lvim-control-center-tabs")
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, 2 + #content_lines)

		local tab_line_len = #tabs_line
		for _, r in ipairs(tab_ranges) do
			local hl = r.active and "ConfigCenterTabActive" or "ConfigCenterTabInactive"
			local start_col = r.start_col
			local end_col = math.min(r.end_col, tab_line_len)
			if end_col > start_col then
				vim.api.nvim_buf_set_extmark(buf, ns_id, 0, start_col, {
					end_col = end_col,
					hl_group = hl,
				})
			end
		end

		if #content_lines > 0 then
			local row = 2 + active_setting_row - 1
			local line_len = #(lines[row + 1] or "")
			if line_len > 0 then
				vim.api.nvim_buf_set_extmark(buf, ns_id, row, 0, {
					end_col = line_len,
					hl_group = "Visual",
				})
			end
		end

		local n_lines = #lines
		local target_row = math.min(2 + active_setting_row, n_lines)
		vim.api.nvim_win_set_cursor(win, { target_row, 0 })
		vim.bo[buf].modifiable = false
	end

	local function set_keymaps()
		local function move_row(delta)
			local group = config.groups[active_tab]
			local count = #(group.settings or {})
			if count == 0 then
				return
			end
			active_setting_row = math.max(1, math.min(count, active_setting_row + delta))
			draw()
		end

		vim.api.nvim_buf_set_keymap(buf, "n", "j", "", {
			nowait = true,
			noremap = true,
			callback = function()
				move_row(1)
			end,
		})
		vim.api.nvim_buf_set_keymap(buf, "n", "k", "", {
			nowait = true,
			noremap = true,
			callback = function()
				move_row(-1)
			end,
		})
		vim.api.nvim_buf_set_keymap(buf, "n", "l", "", {
			nowait = true,
			noremap = true,
			callback = function()
				if active_tab < group_count then
					active_tab = active_tab + 1
					active_setting_row = 1
					draw()
				end
			end,
		})
		vim.api.nvim_buf_set_keymap(buf, "n", "h", "", {
			nowait = true,
			noremap = true,
			callback = function()
				if active_tab > 1 then
					active_tab = active_tab - 1
					active_setting_row = 1
					draw()
				end
			end,
		})
		vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
			nowait = true,
			noremap = true,
			callback = function()
				vim.api.nvim_win_close(win, true)
			end,
		})
		vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
			nowait = true,
			noremap = true,
			callback = function()
				local group = config.groups[active_tab]
				local setting = group.settings and group.settings[active_setting_row]
				if not setting then
					return
				end

				if setting.type == "bool" or setting.type == "boolean" then
					local value = data.load(setting.name)
					if value == nil then
						value = setting.default
					end
					value = not value
					if setting.set then
						setting.set(value)
					else
						data.save(setting.name, value)
					end
					draw()
				elseif setting.type == "select" and setting.options then
					local value = data.load(setting.name)
					if value == nil then
						value = setting.default or setting.options[1]
					end
					local idx = 1
					for i, v in ipairs(setting.options) do
						if v == value then
							idx = i
							break
						end
					end
					local next_val = setting.options[(idx % #setting.options) + 1]
					if setting.set then
						setting.set(next_val)
					else
						data.save(setting.name, next_val)
					end
					draw()
				elseif setting.type == "text" or setting.type == "string" then
					local prompt = "Set " .. (setting.label or setting.name) .. ":"
					vim.ui.input(
						{ prompt = prompt, default = tostring(data.load(setting.name) or setting.default or "") },
						function(input)
							if input then
								if setting.set then
									setting.set(input)
								else
									data.save(setting.name, input)
								end
								draw()
							end
						end
					)
				end
			end,
		})
	end

	set_keymaps()
	draw()
end

return M
