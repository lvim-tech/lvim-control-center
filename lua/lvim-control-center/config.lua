local M = {}

M = {
	save = "~/.local/share/nvim/lvim-control-center",
	window_size = {
		width = 0.8, -- 60% от editor ширината
		height = 0.8, -- 50% от editor височината
	},
	highlights = {
		ConfigCenterTabActive = { fg = "#222436", bg = "#82aaff", bold = true },
		ConfigCenterTabInactive = { fg = "#828bb8", bg = "#222436" },
		ConfigCenterBorder = { fg = "#82aaff", bg = "#1a1b26" },
		ConfigCenterFloat = { fg = "#c8d3f5", bg = "#1a1b26" },
		ConfigCenterTitle = { fg = "#ff966c", bg = "#1a1b26", bold = true },
		ConfigCenterCheckboxOn = { fg = "#a3be8c", bold = true },
		ConfigCenterCheckboxOff = { fg = "#7c7c7c" },
	},
}

if M.save then
	M.save = vim.fn.expand(M.save)
end

return M
