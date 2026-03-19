-- lua/lvim-control-center/config/highlights.lua
-- Named highlight group definitions for lvim-control-center.
-- All colors come from lvim-utils.colors so the palette is shared across plugins.
-- Registered via lvim-utils.highlight — survive colorscheme changes.

local c  = require("lvim-utils.colors")
local hl = require("lvim-utils.highlight")

local M = {}

local function build()
	return {
		LvimCcNormal           = { fg = c.fg,           bg = c.bg_soft_dark },
		LvimCcBorder           = { fg = c.blue,          bg = c.bg_soft_dark },
		LvimCcTitle            = { fg = c.red,            bg = c.bg_soft_dark, bold = true },
		LvimCcSeparator        = { fg = hl.blend(c.blue, c.bg, 0.5) },
		LvimCcFooter           = { fg = c.blue },
		LvimCcFooterKey        = { fg = c.red },
		LvimCcTabActive        = { fg = c.bg_soft_dark,  bg = c.blue,          bold = true },
		LvimCcTabInactive      = { fg = c.fg,             bg = c.bg_soft_dark },
		LvimCcTabIconActive    = { fg = c.red },
		LvimCcTabIconInactive  = { fg = c.orange },
		LvimCcTabTextActive    = { fg = c.bg_soft_dark,  bg = c.blue,          bold = true },
		LvimCcTabTextInactive  = { fg = c.fg,             bg = c.bg_soft_dark },
		LvimCcCursorLine       = { fg = c.bg_soft_dark,  bg = c.blue },
		LvimCcItemIconActive   = { fg = c.red },
		LvimCcItemIconInactive = { fg = c.orange },
		LvimCcItemTextActive   = { fg = c.bg_soft_dark,  bg = c.blue,          bold = true },
		LvimCcItemTextInactive = { fg = c.fg,             bg = c.bg_soft_dark },
		LvimCcSpacer           = { fg = c.red },
	}
end

M.highlights = build()
M.build      = build

return M
