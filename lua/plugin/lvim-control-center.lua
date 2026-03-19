if vim.fn.has("nvim-0.10.0") == 0 then
	print("Lvim Control Center requires Neovim >= 0.10.0")
	return
end

if vim.g.loaded_lvim_control_center then
	return
end
vim.g.loaded_lvim_control_center = true

require("lvim-control-center").setup({})
