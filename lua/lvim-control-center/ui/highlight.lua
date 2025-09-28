local config = require("lvim-control-center.config")

local M = {}

local function is_empty(tbl)
	return not tbl or (type(tbl) == "table" and vim.tbl_isempty(tbl))
end

local function get_highlight_from_theme(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	return ok and hl and not is_empty(hl)
end

M.apply_highlights = function()
	for group, opts in pairs(config.highlights or {}) do
		-- ВИНАГИ сетвай от конфига, ако няма дефинирано в темата (или ако темата е сменила групите)
		if not get_highlight_from_theme(group) then
			vim.api.nvim_set_hl(0, group, {
				fg = opts.fg,
				bg = opts.bg,
				bold = opts.bold,
			})
		end
	end
end

return M
