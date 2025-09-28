local M = {}

M.merge = function(t1, t2)
	for k, v in pairs(t2) do
		if (type(v) == "table") and (type(t1[k] or false) == "table") then
			if M.is_array(t1[k]) then
				t1[k] = M.concat(t1[k], v)
			else
				M.merge(t1[k], t2[k])
			end
		else
			t1[k] = v
		end
	end
	return t1
end

M.concat = function(t1, t2)
	for i = 1, #t2 do
		table.insert(t1, t2[i])
	end
	return t1
end

M.is_array = function(t)
	local i = 0
	for _ in pairs(t) do
		i = i + 1
		if t[i] == nil then
			return false
		end
	end
	return true
end

function M.set_all_windows_option(opt, val, exclude_bt, exclude_ft)
	exclude_bt = exclude_bt or {}
	exclude_ft = exclude_ft or {}
	local cur_win = vim.api.nvim_get_current_win()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local bt = vim.bo[buf].buftype
		local ft = vim.bo[buf].filetype
		local skip = false

		for _, ebt in ipairs(exclude_bt) do
			if bt == ebt then
				skip = true
				break
			end
		end
		if not skip then
			for _, eft in ipairs(exclude_ft) do
				if ft == eft then
					skip = true
					break
				end
			end
		end

		if not skip then
			vim.api.nvim_set_current_win(win)
			pcall(function()
				vim.wo.number = val
			end)
		end
	end
	-- върни се на оригиналния прозорец
	vim.api.nvim_set_current_win(cur_win)
end

return M
