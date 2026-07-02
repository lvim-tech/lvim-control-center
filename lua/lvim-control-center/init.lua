-- lvim-control-center: plugin entry point. Call M.setup() once from your Neovim config to
-- deep-merge user overrides into the live config, initialise the SQLite database, register
-- the :LvimControlCenter user command, and re-apply the settings persisted from a prior
-- session. The UI is built lazily on first open (see lvim-control-center.ui), so setup()
-- stays cheap and does not require lvim-utils.ui to be present at startup.
--
---@module "lvim-control-center"

local config = require("lvim-control-center.config")
local db = require("lvim-control-center.persistence.db")
local utils = require("lvim-utils.utils")
local commands = require("lvim-control-center.commands")

local M = {}

--- Initialise the control center. Must be called before any other API usage.
--- The panel's "lvim-utils-ui" filetype is registered with the cursor module centrally
--- (lvim-utils dependencies `cursor = { ft = { "lvim-utils-ui" } }`), so no per-plugin
--- cursor.setup call is made here (it would only duplicate the central registration).
---@param opts? LvimControlCenterConfig  Partial config, deep-merged into defaults. Omit/nil = defaults as-is.
---@return nil
function M.setup(opts)
    -- Deep-merge user overrides into the default config table (in place, so every reader sees them).
    if opts ~= nil then
        utils.merge(config, opts)
    end

    -- Initialise the SQLite persistence layer.
    db.init(config.save)

    -- Register the :LvimControlCenter user command and apply persisted settings.
    commands.init()
end

return M
