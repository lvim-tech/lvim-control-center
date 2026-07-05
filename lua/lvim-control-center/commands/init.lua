-- lvim-control-center.commands: registers ONE instance's user command (open in a layout /
-- jump to a tab or setting / export / import / reset). The command name comes from the
-- instance (`instance.config.command`), so several instances each get their own command.
-- The command's completion doubles as a search across that instance's groups + settings, so
-- a bare name jumps straight to its group.
--
---@module "lvim-control-center.commands"

local M = {}

--- Resolve the group of a setting by its name within an instance (so a bare setting name can
--- be jumped to).
---@param instance LvimControlCenterInstance
---@param name string
---@return string|nil group_name, string|nil setting_name
local function group_of_setting(instance, name)
    for _, group in ipairs(instance.config.groups or {}) do
        for _, setting in ipairs(group.settings or {}) do
            if setting.name == name then
                return group.name, setting.name
            end
        end
    end
    return nil, nil
end

--- Register the instance's user command. Called once from instance.new().
---@param instance LvimControlCenterInstance
---@return nil
function M.register(instance)
    local cmd = instance.config.command
    -- :<Command> [float|area|bottom] [tab] [row]  open in a layout (default float), optionally focused
    -- :<Command> <setting>        open focused on a setting (group resolved for you)
    -- :<Command> export [path]    export this instance's persisted settings to JSON
    -- :<Command> import [path]    import this instance's persisted settings from JSON
    -- :<Command> reset [setting]  reset one setting (or all) to defaults
    vim.api.nvim_create_user_command(cmd, function(opts)
        -- Pull an optional LAYOUT token (float / area / bottom — order-independent) out of the args; it picks
        -- where the panel docks. The remaining args are the export/import/reset verb or the tab / setting / row.
        local LAYOUTS = { float = true, area = true, bottom = true }
        local layout, rest = nil, {}
        for _, a in ipairs(opts.fargs) do
            if LAYOUTS[a] and not layout then
                layout = a
            else
                rest[#rest + 1] = a
            end
        end
        local a1, a2 = rest[1], rest[2]
        if a1 == "export" then
            instance:export(a2)
        elseif a1 == "import" then
            instance:import(a2)
        elseif a1 == "reset" then
            local count = instance:reset(a2)
            vim.notify(
                ("Reset %d setting(s)%s"):format(count, a2 and (": " .. a2) or " to defaults"),
                vim.log.levels.INFO,
                { title = "Control Center" }
            )
        elseif a1 and not a2 then
            -- a single arg may be a group OR a setting name — resolve a bare setting to its group.
            local g, s = group_of_setting(instance, a1)
            if g then
                instance:open(g, s, layout)
            else
                instance:open(a1, nil, layout)
            end
        else
            instance:open(a1, a2, layout)
        end
    end, {
        desc = ("Open %s ([float|area|bottom] layout; or export/import/reset settings)"):format(cmd),
        nargs = "*",
        complete = function(arglead, cmdline)
            local words = vim.split(vim.trim(cmdline), "%s+")
            local cands = {}
            if #words <= 2 then
                -- first arg: special verbs + group names + every setting name (search/discovery)
                cands = { "export", "import", "reset", "float", "area", "bottom" }
                for _, group in ipairs(instance.config.groups or {}) do
                    cands[#cands + 1] = group.name
                    for _, setting in ipairs(group.settings or {}) do
                        cands[#cands + 1] = setting.name
                    end
                end
            else
                -- second arg: setting names within the chosen group
                for _, group in ipairs(instance.config.groups or {}) do
                    if group.name == words[2] then
                        for _, setting in ipairs(group.settings or {}) do
                            cands[#cands + 1] = setting.name
                        end
                    end
                end
            end
            return vim.tbl_filter(function(c)
                return c:find(arglead, 1, true) == 1
            end, cands)
        end,
    })
end

return M
