local config = require("lvim-control-center.config")
local highlight = require("lvim-control-center.ui.highlight")
local data = require("lvim-control-center.persistence.data")

local M = {}

local function render_setting_line(setting, value)
	local label = setting.label or setting.desc or setting.name
	local t = setting.type
	if t == "bool" or t == "boolean" then
		return string.format(" %s %s", value and config.icons.is_true or config.icons.is_false, label)
	elseif t == "select" then
		return string.format(" %s %s: %s", config.icons.is_select, label, value)
	elseif t == "int" or t == "integer" then
		return string.format(" %s %s: %d", config.icons.is_int, label, value or 0)
	elseif t == "float" or t == "number" then
		return string.format(" %s %s: %s", config.icons.is_float, label, value or 0)
	elseif t == "action" then
		return string.format(" %s %s", config.icons.is_action or "", label)
	else
		return string.format(" %s %s: %s", config.icons.is_string, label, value)
	end
end

local function get_settings_lines(group)
	local lines = {}
	if group and group.settings then
		for _, setting in ipairs(group.settings) do
			local value
			if setting.type == "action" then
				value = nil
			elseif setting.get then
				pcall(function()
					value = setting.get()
				end)
			end
			if value == nil and setting.type ~= "action" then
				value = data.load(setting.name)
			end
			if value == nil and setting.default ~= nil and setting.type ~= "action" then
				value = setting.default
			end
			local line = render_setting_line(setting, value)
			table.insert(lines, line)
		end
	end
	return lines
end

local function apply_cursor_blending(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end

	local augroup_name = "LvimControlCenterCursorBlend"
	local cursor_blend_augroup = vim.api.nvim_create_augroup(augroup_name, { clear = true })
	vim.cmd("hi Cursor blend=100")
	vim.api.nvim_create_autocmd({ "WinLeave", "WinEnter" }, {
		group = cursor_blend_augroup,
		callback = function()
			local current_event_win = vim.api.nvim_get_current_win()
			local blend_value = current_event_win == win and 100 or 0
			vim.cmd("hi Cursor blend=" .. blend_value)
		end,
	})
end

M.open = function(tab_selector, id_or_row)
	highlight.apply_highlights()

	-- Запази буфера, от който е стартиран плъгина
	local origin_bufnr = vim.api.nvim_get_current_buf()

	-- Търси таб по label или name (label има приоритет)
	local active_tab = 1
	if tab_selector then
		for i, group in ipairs(config.groups) do
			if group.label == tab_selector or group.name == tab_selector then
				active_tab = i
				break
			end
		end
	end

	local group = config.groups[active_tab]
	local active_setting_row = 1
	if id_or_row and group and group.settings then
		local idx = tonumber(id_or_row)
		if idx and group.settings[idx] then
			active_setting_row = idx
		else
			for i, setting in ipairs(group.settings) do
				if setting.name == id_or_row then
					active_setting_row = i
					break
				end
			end
		end
	end

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
		zindex = 10,
		border = config.border or "single",
		style = "minimal",
		noautocmd = true,
	})
	_G.LVIM_CONTROL_CENTER_WIN = win

	vim.bo[buf].filetype = "lvim-control-center"

	vim.api.nvim_set_option_value(
		"winhighlight",
		"Normal:LvimControlCenterPanel,FloatBorder:LvimControlCenterBorder,Title:LvimControlCenterTitle",
		{ win = win }
	)

	apply_cursor_blending(win)

	local function draw()
		vim.bo[buf].modifiable = true
		local lines = {}
		local tabs = {}
		local tab_ranges = {}
		local col = 0
		for i, group_iter in ipairs(config.groups) do
			local icon = group_iter.icon or ""
			local has_icon = icon ~= ""
			local tab_label = group_iter.label or group_iter.name
			local name = " " .. icon .. (has_icon and " " or "") .. tab_label .. " "
			table.insert(tabs, name)

			local tab_start_col = col
			local tab_end_col = col + #name
			local icon_start_col = has_icon and (tab_start_col + 1) or -1
			local icon_end_col = has_icon and (icon_start_col + #icon) or -1

			table.insert(tab_ranges, {
				active = (i == active_tab),
				tab_start_col = tab_start_col,
				tab_end_col = tab_end_col,
				icon_start_col = icon_start_col,
				icon_end_col = icon_end_col,
				has_icon = has_icon,
			})
			col = tab_end_col
		end

		local tabs_line = table.concat(tabs, "")
		table.insert(lines, tabs_line)

		local sep = string.rep("─", width)
		table.insert(lines, sep)

		local current_group = config.groups[active_tab]
		local content_lines = get_settings_lines(current_group)

		for _, l in ipairs(content_lines) do
			table.insert(lines, l)
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

		local ns_id = vim.api.nvim_create_namespace("lvim-control-center-tabs")
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

		local sep_byte_len = #sep
		vim.api.nvim_buf_set_extmark(buf, ns_id, 1, 0, {
			end_col = sep_byte_len,
			hl_group = "LvimControlCenterSeparator",
		})

		for _, r in ipairs(tab_ranges) do
			local tab_hl = r.active and "LvimControlCenterTabActive" or "LvimControlCenterTabInactive"
			local icon_hl = r.active and "LvimControlCenterTabIconActive" or "LvimControlCenterTabIconInactive"

			vim.api.nvim_buf_set_extmark(buf, ns_id, 0, r.tab_start_col, {
				end_col = r.tab_end_col,
				hl_group = tab_hl,
				priority = 80,
			})

			if r.has_icon then
				vim.api.nvim_buf_set_extmark(buf, ns_id, 0, r.icon_start_col, {
					end_col = r.icon_end_col,
					hl_group = icon_hl,
					priority = 90,
				})
			end
		end

		for i, line in ipairs(content_lines) do
			local is_active = (active_setting_row == i)
			local icon_hl = is_active and "LvimControlCenterIconActive" or "LvimControlCenterIconInactive"
			local line_hl = is_active and "LvimControlCenterLineActive" or "LvimControlCenterLineInactive"

			local icon_len = vim.str_utfindex(line:sub(1, 5))
			if icon_len > 0 then
				vim.api.nvim_buf_set_extmark(buf, ns_id, i + 1, 0, {
					end_col = icon_len,
					hl_group = icon_hl,
					priority = 100,
				})
			end

			local text_byte_len = #line
			if text_byte_len > 0 then
				vim.api.nvim_buf_set_extmark(buf, ns_id, i + 1, 0, {
					end_col = text_byte_len,
					hl_group = line_hl,
					priority = 90,
					hl_mode = "blend",
				})
			end

			local disp = vim.fn.strdisplaywidth(line)
			local fill = math.max(0, width - disp)
			if fill > 0 then
				local fill_spaces = string.rep(" ", fill)
				vim.api.nvim_buf_set_extmark(buf, ns_id, i + 1, 0, {
					virt_text = { { fill_spaces, line_hl } },
					virt_text_win_col = disp,
					priority = 90,
					hl_mode = "blend",
				})
			end
		end

		local target_row = 1 + active_setting_row
		vim.api.nvim_win_set_cursor(win, { target_row, 0 })
		vim.bo[buf].modifiable = false
	end

	local function set_keymaps()
		local function move_row(delta)
			local group_move = config.groups[active_tab]
			local count = #(group_move.settings or {})
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
				local group_cr = config.groups[active_tab]
				local setting = group_cr.settings and group_cr.settings[active_setting_row]
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
						setting.set(value, nil, origin_bufnr)
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
						setting.set(next_val, nil, origin_bufnr)
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
									setting.set(input, nil, origin_bufnr)
								else
									data.save(setting.name, input)
								end
								draw()
							end
						end
					)
				elseif setting.type == "int" or setting.type == "integer" then
					local prompt = "Set " .. (setting.label or setting.name) .. ":"
					vim.ui.input(
						{ prompt = prompt, default = tostring(data.load(setting.name) or setting.default or "") },
						function(input)
							if input then
								local num = tonumber(input)
								if num and math.floor(num) == num then
									if setting.set then
										setting.set(num, nil, origin_bufnr)
									else
										data.save(setting.name, num)
									end
									draw()
								else
									vim.notify("Please enter a valid integer!", vim.log.levels.ERROR)
								end
							end
						end
					)
				elseif setting.type == "float" or setting.type == "number" then
					local prompt = "Set " .. (setting.label or setting.name) .. ":"
					vim.ui.input(
						{ prompt = prompt, default = tostring(data.load(setting.name) or setting.default or "") },
						function(input)
							if input then
								local num = tonumber(input)
								if num then
									if setting.set then
										setting.set(num, nil, origin_bufnr)
									else
										data.save(setting.name, num)
									end
									draw()
								else
									vim.notify("Please enter a valid number!", vim.log.levels.ERROR)
								end
							end
						end
					)
				elseif setting.type == "action" then
					if setting.run and type(setting.run) == "function" then
						setting.run(origin_bufnr)
					else
						vim.notify("No action defined for: " .. (setting.label or setting.name), vim.log.levels.WARN)
					end
					draw()
				end
			end,
		})

		vim.api.nvim_buf_set_keymap(buf, "n", "<BS>", "", {
			nowait = true,
			noremap = true,
			callback = function()
				local group_bs = config.groups[active_tab]
				local setting = group_bs.settings and group_bs.settings[active_setting_row]

				if not setting or setting.type ~= "select" or not setting.options then
					return
				end

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

				local prev_idx = idx - 1
				if prev_idx < 1 then
					prev_idx = #setting.options
				end

				local prev_val = setting.options[prev_idx]

				if setting.set then
					setting.set(prev_val, nil, origin_bufnr)
				else
					data.save(setting.name, prev_val)
				end

				draw()
			end,
		})
	end

	set_keymaps()
	draw()
end

return M
