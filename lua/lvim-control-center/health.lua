-- lvim-control-center.health: :checkhealth lvim-control-center — probes the hard
-- dependencies (Neovim version, sqlite.lua for persistence, lvim-utils/lvim-ui for the UI +
-- deep-merge) and then reports EVERY live instance: its command, its database state, and its
-- registered groups / settings, so a mis-declared config surfaces at a glance.
--
---@module "lvim-control-center.health"

local instance = require("lvim-control-center.instance")

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

    -- lvim-utils / lvim-ui — mandatory: provide the UI panel and the deep-merge used by new().
    local ok_utils = pcall(require, "lvim-utils.utils")
    local ok_ui = pcall(require, "lvim-ui")
    if ok_utils and ok_ui then
        health.ok("lvim-utils + lvim-ui found (UI panel + config merge)")
    else
        health.error("lvim-utils / lvim-ui not found — the panel cannot render and new() cannot merge config")
    end

    -- Per-instance summary. No instance yet is fine (nothing has called new()).
    local n = 0
    for command, inst in pairs(instance._instances) do
        n = n + 1
        local groups = inst.config.groups or {}
        local n_settings = 0
        for _, group in ipairs(groups) do
            n_settings = n_settings + #(group.settings or {})
        end
        health.start(("instance :%s"):format(command))
        if inst.db and inst.db:is_open() then
            health.ok("database open: " .. tostring(inst.config.save))
        else
            health.warn("database NOT open: " .. tostring(inst.config.save))
        end
        health.info(("%d group(s), %d setting(s) registered"):format(#groups, n_settings))
        health.info(("title_pos: %s"):format(tostring(inst.config.title_pos)))
    end
    if n == 0 then
        health.info("no instances created yet — call require('lvim-control-center').new({ command = … })")
    end
end

return M
