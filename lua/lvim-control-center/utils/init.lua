-- lua/lvim-control-center/utils/init.lua
-- General-purpose table utilities used across the plugin.

local M = {}

--- Deep-merge t2 into t1 in-place.
--- - Nested maps are merged recursively.
--- - Arrays (sequential tables) are concatenated rather than replaced.
--- - All other values in t2 overwrite the corresponding key in t1.
---@param t1 table  Target table (modified in-place)
---@param t2 table  Source table to merge from
---@return table  t1
function M.merge(t1, t2)
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

--- Append all elements of t2 to t1 in-place and return t1.
---@param t1 any[]  Base array (modified in-place)
---@param t2 any[]  Elements to append
---@return any[]  t1
function M.concat(t1, t2)
	for i = 1, #t2 do
		table.insert(t1, t2[i])
	end
	return t1
end

--- Return true when t is a proper sequential array (no holes, integer keys only).
---@param t table
---@return boolean
function M.is_array(t)
	local i = 0
	for _ in pairs(t) do
		i = i + 1
		if t[i] == nil then
			return false
		end
	end
	return true
end

return M
