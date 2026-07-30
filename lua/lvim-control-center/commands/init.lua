-- lvim-control-center.commands: user commands for the control center.
--   • M.register(instance)   — ONE per-instance command named `instance.config.command`: open in a
--     layout / jump to a tab or setting / search / export / import / reset / preset (save|load|delete|
--     list). Its completion doubles as a search across that instance's groups + settings.
--   • M.ensure_global(registry) — the cross-instance `:LvimControlCenterList` (registered once): pick
--     a live instance to open it.
--
---@module "lvim-control-center.commands"

local uconfig = require("lvim-control-center.config")
local M = {}

--- Resolve the group of a setting by its name within an instance (so a bare setting name can
--- be jumped to).
---@param instance LvimControlCenterInstance
---@param name string
---@return string|nil group_name, string|nil setting_name
local function group_of_setting(instance, name)
    for _, group in ipairs(instance.config.groups or {}) do
        for _, setting in ipairs(uconfig.settings_of(group)) do
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
        local LAYOUTS = { float = true, area = true, bottom = true }
        local layout, rest = nil, vim.list_extend({}, opts.fargs)
        if LAYOUTS[rest[1]] then
            layout = table.remove(rest, 1)
        end
        local a1, a2 = rest[1], rest[2]
        -- Host subcommands (e.g. quick toggles) take priority over the built-in verbs, so a plugin can
        -- extend THIS command instead of registering a second one. Remaining args are forwarded.
        local subs = instance.config.subcommands or {}
        if a1 and type(subs[a1]) == "function" then
            subs[a1](unpack(rest, 2))
            return
        end
        if a1 == "export" then
            instance:export(a2)
        elseif a1 == "import" then
            instance:import(a2)
        elseif a1 == "search" then
            instance:search()
        elseif a1 == "preset" then
            local action, pname = rest[2], rest[3]
            if action == "save" and pname then
                local ok = instance:preset_save(pname)
                vim.notify(
                    ok and ("Saved preset: " .. pname) or "Preset save failed",
                    ok and vim.log.levels.INFO or vim.log.levels.ERROR,
                    { title = "Control Center" }
                )
            elseif action == "load" and pname then
                local ok = instance:preset_load(pname)
                vim.notify(
                    ok and ("Loaded preset: " .. pname) or ("No such preset: " .. pname),
                    ok and vim.log.levels.INFO or vim.log.levels.WARN,
                    { title = "Control Center" }
                )
            elseif action == "delete" and pname then
                local ok = instance:preset_delete(pname)
                vim.notify(
                    ok and ("Deleted preset: " .. pname) or ("Delete failed: " .. pname),
                    ok and vim.log.levels.INFO or vim.log.levels.WARN,
                    { title = "Control Center" }
                )
            else
                -- "preset" / "preset list" → show what's saved.
                local names = instance:preset_list()
                vim.notify(
                    #names > 0 and ("Presets: " .. table.concat(names, ", ")) or "No presets saved.",
                    vim.log.levels.INFO,
                    { title = "Control Center" }
                )
            end
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
        desc = ("Open %s ([float|area|bottom]; or search/export/import/reset/preset)"):format(cmd),
        nargs = "*",
        complete = function(arglead, cmdline)
            -- Preserve a trailing empty slot when the line ends in whitespace: the user has started
            -- a NEW argument, so `:<Cmd> general <Tab>` must count as arg 2 (settings of "general"),
            -- not arg 1. vim.trim would eat that space and misplace the position — strip only the
            -- LEADING whitespace and keep empty fields.
            local words = vim.split((cmdline:gsub("^%s+", "")), "%s+", { trimempty = false })
            -- Mirror the runtime parse: a leading layout token (float/area/bottom) is stripped before the
            -- args are interpreted (see the command body), so drop it here too — otherwise every downstream
            -- `words[2]` switch is off by one (`:Cmd float <Tab>` would look for a group literally named
            -- "float" and offer nothing).
            if words[2] == "float" or words[2] == "area" or words[2] == "bottom" then
                table.remove(words, 2)
            end
            local cands = {}
            if words[2] == "preset" then
                -- `preset <action> [name]`
                if #words <= 3 then
                    cands = { "save", "load", "delete", "list" }
                elseif words[3] == "load" or words[3] == "delete" then
                    cands = instance:preset_list()
                end
            elseif #words <= 2 then
                -- FIRST ARG: the things you can ASK THIS COMMAND TO DO — its verbs, the host's own
                -- subcommands, and the layout tokens. Group and setting names are deliberately NOT offered
                -- here, even though the command still ACCEPTS them (`:<Cmd> Spelling`, `:<Cmd> spell_active`):
                -- listing every setting turned one <Tab> into a wall mixing real commands with internal keys
                -- (`config_sep`, `show_path`), which is the opposite of a hint. Discovery has its own verb —
                -- `search` — which fuzzy-finds any setting and opens the panel on it.
                cands = { "search", "export", "import", "reset", "preset", "float", "area", "bottom" }
                for name in pairs(instance.config.subcommands or {}) do
                    cands[#cands + 1] = name
                end
            else
                -- second arg: setting names within the chosen group
                for _, group in ipairs(instance.config.groups or {}) do
                    if group.name == words[2] then
                        for _, setting in ipairs(uconfig.settings_of(group)) do
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

--- The cross-instance registry command (`:LvimControlCenterList`). Registered once, idempotent —
--- backed by the live-instance registry passed from instance.new(). Selecting an instance opens
--- its panel.
---@type boolean
local _global_registered = false

--- Register `:LvimControlCenterList` once. Safe to call on every new().
---@param registry table<string, LvimControlCenterInstance>  the live-instance registry
---@return nil
function M.ensure_global(registry)
    if _global_registered then
        return
    end
    _global_registered = true
    vim.api.nvim_create_user_command("LvimControlCenterList", function()
        local items = {}
        for command, inst in pairs(registry) do
            local nset = 0
            for _, g in ipairs(inst.config.groups or {}) do
                nset = nset + #(g.settings or {})
            end
            items[#items + 1] = {
                command = command,
                instance = inst,
                label = ("%-26s  %d groups · %d settings"):format(":" .. command, #(inst.config.groups or {}), nset),
            }
        end
        if #items == 0 then
            vim.notify("No control center instances registered.", vim.log.levels.INFO, { title = "Control Center" })
            return
        end
        table.sort(items, function(a, b)
            return a.command < b.command
        end)
        local ok, lui = pcall(require, "lvim-ui")
        if not ok then
            return
        end
        lui.select({
            title = "Instances",
            items = items,
            callback = function(confirmed, index)
                local it = confirmed and items[index]
                if it then
                    it.instance:open()
                end
            end,
        })
    end, { desc = "List / open lvim-control-center instances" })
end

return M
