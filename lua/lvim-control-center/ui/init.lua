local config = require("lvim-control-center.config")
local highlight = require("lvim-control-center.ui.highlight")
local data = require("lvim-control-center.persistence.data")

local M = {}

local function render_setting_line(setting, value)
	local label = setting.label or setting.desc or setting.name
	local t = setting.type
	if t == "bool" or t == "boolean" then
		return string.format(" %s %s", value and "󰄳" or "󰄰", label)
	elseif t == "select" then
		return string.format("  %s: %s", label, value)
	else
		return string.format("  %s: %s", label, value)
	end
end

-- Returns just lines; highlights are handled in draw!
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
		border = config.border or "rounded",
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
			local icon = group.icon or ""
			local has_icon = icon ~= ""
			local name = " " .. icon .. (has_icon and " " or "") .. group.name .. " "
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

		-- separator line has exactly 'width' display columns; use same char repeated
		local sep = string.rep("─", width)
		table.insert(lines, sep)

		local group = config.groups[active_tab]
		local content_lines = get_settings_lines(group)

		-- write content_lines AS IS (no padding)
		for _, l in ipairs(content_lines) do
			table.insert(lines, l)
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

		local ns_id = vim.api.nvim_create_namespace("lvim-control-center-tabs")
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

		-- highlight separator line (row index 1 in buf is second line)
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

		-- Highlight content lines: highlight existing text, then add virt_text_win_col to fill rest to window width
		for i, line in ipairs(content_lines) do
			local is_active = (active_setting_row == i)
			local icon_hl = is_active and "LvimControlCenterIconActive" or "LvimControlCenterIconInactive"
			local line_hl = is_active and "LvimControlCenterLineActive" or "LvimControlCenterLineInactive"

			-- icon area (use utf-aware small slice to get visual icon length)
			local icon_len = vim.str_utfindex(line:sub(1, 5))
			if icon_len > 0 then
				vim.api.nvim_buf_set_extmark(buf, ns_id, i + 1, 0, {
					end_col = icon_len,
					hl_group = icon_hl,
					priority = 100,
				})
			end

			-- highlight the actual text that exists in the buffer (end_col uses byte length)
			local text_byte_len = #line
			if text_byte_len > 0 then
				vim.api.nvim_buf_set_extmark(buf, ns_id, i + 1, 0, {
					end_col = text_byte_len,
					hl_group = line_hl,
					priority = 90,
					hl_mode = "blend",
				})
			end

			-- fill the remaining display width with virt_text placed exactly at the visual column
			local disp = vim.fn.strdisplaywidth(line)
			local fill = math.max(0, width - disp)
			if fill > 0 then
				local fill_spaces = string.rep(" ", fill)
				-- Use virt_text_win_col to position the virt_text at the exact screen column (avoids the 1-col gap)
				vim.api.nvim_buf_set_extmark(buf, ns_id, i + 1, 0, {
					virt_text = { { fill_spaces, line_hl } },
					virt_text_win_col = disp,
					priority = 90,
					hl_mode = "blend",
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
