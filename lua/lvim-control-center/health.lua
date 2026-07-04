-- lvim-control-center.health: :checkhealth lvim-control-center — probes the hard
-- dependencies (Neovim version, sqlite.lua for persistence, lvim-utils for the UI +
-- deep-merge), reports whether the SQLite database is open, and summarises the registered
-- groups / settings so a mis-declared config surfaces at a glance.
--
---@module "lvim-control-center.health"

local config = require("lvim-control-center.config")
local db = require("lvim-control-center.persistence.db")

local M = {}

--- Run the health checks.
---@return nil
function M.check()
    local health = vim.health
    health.start("lvim-control-center")

    -- Neovim version: vim.uv + the lvim-utils UI both need >= 0.10.
    if vim.fn.has("nvim-0.10") == 1 then
        health.ok("Neovim >= 0.10")
    else
        health.error("Neovim >= 0.10 is required")
    end

    -- sqlite.lua — mandatory: the whole persistence layer is built on it.
    local ok_sqlite = pcall(require, "sqlite.db")
    if ok_sqlite then
        health.ok("sqlite.lua found (settings persistence)")
    else
        health.error("sqlite.lua not found — settings cannot be persisted (install kkharji/sqlite.lua)")
    end

    -- lvim-utils — mandatory: provides the UI panel and the deep-merge used by setup().
    local ok_utils = pcall(require, "lvim-utils.utils")
    local ok_ui = pcall(require, "lvim-ui")
    if ok_utils and ok_ui then
        health.ok("lvim-utils found (UI panel + config merge)")
    else
        health.error("lvim-utils not found — the panel cannot render and setup() cannot merge config")
    end

    -- Database connection state (init() runs during setup()).
    if db.db and db.settings then
        health.ok("SQLite database initialised")
    else
        health.warn("SQLite database not initialised — was setup() called (and is sqlite.lua present)?")
    end

    -- Config summary: total groups + settings so a mis-declared config is visible.
    local groups = config.groups or {}
    local n_settings = 0
    for _, group in ipairs(groups) do
        n_settings = n_settings + #(group.settings or {})
    end
    if #groups > 0 then
        health.ok(("%d group(s), %d setting(s) registered"):format(#groups, n_settings))
    else
        health.info("no groups registered yet — declare groups in setup({ groups = { … } })")
    end

    health.info(("save dir: %s  title_pos: %s"):format(tostring(config.save), tostring(config.title_pos)))
end

return M
