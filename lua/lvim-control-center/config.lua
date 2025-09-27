local M = {}

M = {
	save = "~/.local/share/nvim/lvim-space",
}

if M.save then
	M.save = vim.fn.expand(M.save)
end

return M
