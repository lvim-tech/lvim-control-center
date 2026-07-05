-- lvim-control-center: plugin entry point. Multi-instance — there is NO global singleton.
--
--   • Programmatic (the real API):
--       local cc = require("lvim-control-center")
--       local panel = cc.new({ command = "LvimControlCenter", groups = { … } })
--       panel:open()                              -- :reset() :export() :import() :close()
--
--   • Declarative (for the generic lvim-nvim loader, which calls setup(opts)):
--       setup({ command = "LvimControlCenter", groups = { … } })   -- one instance
--       setup({ { command = "A", … }, { command = "B", … } })      -- several instances
--     setup() is a thin forwarder over new() — it holds no state of its own. Called with no
--     command (or an empty table) it is a no-op, so a present-but-unconfigured plugin loads
--     cleanly.
--
-- Each instance owns its config, its OWN SQLite database, its user command and its open-state
-- (see instance.lua). Building the UI is lazy (first open), so new() stays cheap and does not
-- require lvim-ui at startup.
--
-- Registry helpers: get(command), list(), close_all(), and whole-profile export_all(path) /
-- import_all(path) across every instance. The cross-instance `:LvimControlCenterList` command
-- (registered by instance.new) picks a live instance to open.
--
---@module "lvim-control-center"

local instance = require("lvim-control-center.instance")

local M = {}

--- Create a control center instance. Requires a unique `opts.command`.
---@type fun(opts: LvimControlCenterConfig): LvimControlCenterInstance
M.new = instance.new

--- Look up a live instance by its command name.
---@param command string
---@return LvimControlCenterInstance|nil
function M.get(command)
    return instance._instances[command]
end

--- Loader-facing forwarder over new(). Accepts a SINGLE instance opts (`{ command = … }`) or
--- a LIST of them (`{ {command=…}, {command=…} }`). Lenient: no command / empty / nil → no-op.
---@param opts? LvimControlCenterConfig|LvimControlCenterConfig[]
---@return LvimControlCenterInstance|LvimControlCenterInstance[]|nil
function M.setup(opts)
    if type(opts) ~= "table" then
        return
    end
    -- A list of instance option tables (array part present) → build each.
    if opts[1] ~= nil then
        local built = {}
        for _, o in ipairs(opts) do
            if type(o) == "table" and o.command then
                built[#built + 1] = instance.new(o)
            end
        end
        return built
    end
    -- A single instance — but only when configured with a command (otherwise a quiet no-op).
    if opts.command == nil then
        return
    end
    return instance.new(opts)
end

--- List every live instance (command, save dir, group/setting counts, open-state). Sorted by command.
---@return { command: string, save: string, groups: integer, settings: integer, is_open: boolean, instance: LvimControlCenterInstance }[]
function M.list()
    local out = {}
    for command, inst in pairs(instance._instances) do
        local nset = 0
        for _, g in ipairs(inst.config.groups or {}) do
            nset = nset + #(g.settings or {})
        end
        out[#out + 1] = {
            command = command,
            save = inst.config.save,
            groups = #(inst.config.groups or {}),
            settings = nset,
            is_open = inst._is_open,
            instance = inst,
        }
    end
    table.sort(out, function(a, b)
        return a.command < b.command
    end)
    return out
end

--- Close every live instance (drops each command + closes each database).
---@return nil
function M.close_all()
    -- Snapshot first: :close() mutates the registry, which is unsafe to do while iterating it.
    local all = {}
    for _, inst in pairs(instance._instances) do
        all[#all + 1] = inst
    end
    for _, inst in ipairs(all) do
        inst:close()
    end
end

--- Snapshot EVERY instance's settings into ONE JSON file, keyed by command — a whole-profile export.
---@param path? string
---@return nil
function M.export_all(path)
    path = vim.fs.normalize(path or (vim.fn.stdpath("data") .. "/lvim-control-center-all-export.json"))
    local snapshot = {}
    for command, inst in pairs(instance._instances) do
        snapshot[command] = inst:settings_map()
    end
    local ok = pcall(vim.fn.writefile, { vim.fn.json_encode(snapshot) }, path)
    if ok then
        vim.notify(
            ("Exported %d instance(s) → %s"):format(vim.tbl_count(snapshot), path),
            vim.log.levels.INFO,
            { title = "Control Center" }
        )
    else
        vim.notify("Export failed: " .. path, vim.log.levels.ERROR, { title = "Control Center" })
    end
end

--- Import a whole-profile JSON (from export_all): apply each command's settings to its live instance.
--- Entries whose command has no live instance are skipped. Returns the count applied.
---@param path? string
---@return integer
function M.import_all(path)
    path = vim.fs.normalize(path or (vim.fn.stdpath("data") .. "/lvim-control-center-all-export.json"))
    if vim.fn.filereadable(path) == 0 then
        vim.notify("No such file: " .. path, vim.log.levels.ERROR, { title = "Control Center" })
        return 0
    end
    local ok, map = pcall(vim.fn.json_decode, table.concat(vim.fn.readfile(path), "\n"))
    if not ok or type(map) ~= "table" then
        vim.notify("Invalid import file: " .. path, vim.log.levels.ERROR, { title = "Control Center" })
        return 0
    end
    local applied = 0
    for command, settings in pairs(map) do
        local inst = instance._instances[command]
        if inst and type(settings) == "table" then
            inst.data:import_all(settings)
            inst:apply_saved_settings()
            applied = applied + 1
        end
    end
    vim.notify(("Imported %d instance(s)"):format(applied), vim.log.levels.INFO, { title = "Control Center" })
    return applied
end

return M
