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

return M
