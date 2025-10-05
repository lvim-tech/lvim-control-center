local M = {}

M = {
	save = "~/.local/share/nvim/lvim-control-center",
	window_size = {
		width = 0.8,
		height = 0.8,
	},
	border = { " ", " ", " ", " ", " ", " ", " ", " " },
	icons = {
		is_true = "",
		is_false = "",
		is_select = "󱖫",
		is_int = "󰎠",
		is_float = "",
		is_string = "󰬶",
		is_action = "",
	},
	highlights = {
		LvimControlCenterPanel = { fg = "#505067", bg = "#1a1a22" },
		LvimControlCenterSeparator = { fg = "#4a6494" },
		LvimControlCenterTabActive = { fg = "#1a1a22", bg = "#4a6494", bold = true },
		LvimControlCenterTabInactive = { fg = "#505067", bg = "#1a1a22" },
		LvimControlCenterTabIconActive = { fg = "#b65252" },
		LvimControlCenterTabIconInactive = { fg = "#a26666" },
		LvimControlCenterBorder = { fg = "#4a6494", bg = "#1a1a22" },
		LvimControlCenterTitle = { fg = "#b65252", bg = "#1a1a22", bold = true },
		LvimControlCenterLineActive = { fg = "#1a1a22", bg = "#4a6494", bold = true },
		LvimControlCenterLineInactive = { fg = "#505067", bg = "#1a1a22" },
		LvimControlCenterIconActive = { fg = "#b65252" },
		LvimControlCenterIconInactive = { fg = "#a26666" },
	},
}

if M.save then
	M.save = vim.fn.expand(M.save)
end

return M
