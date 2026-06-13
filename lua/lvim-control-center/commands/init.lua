-- lua/lvim-control-center/commands/init.lua
-- Registers Neovim user commands and applies settings that were persisted from
-- a previous session.

local ui = require("lvim-control-center.ui")
local data = require("lvim-control-center.persistence.data")
local config = require("lvim-control-center.config")

local M = {}

local DEFAULT_EXPORT = vim.fn.stdpath("data") .. "/lvim-control-center-export.json"

--- Export all persisted settings to a JSON file.
---@param path? string
local function export_settings(path)
    path = vim.fn.expand(path or DEFAULT_EXPORT)
    local map = data.export_all()
    local ok = pcall(vim.fn.writefile, { vim.fn.json_encode(map) }, path)
    if ok then
        vim.notify(("Exported %d settings → %s"):format(vim.tbl_count(map), path), vim.log.levels.INFO, {
            title = "Control Center",
        })
    else
        vim.notify("Export failed: " .. path, vim.log.levels.ERROR, { title = "Control Center" })
    end
end

--- Import persisted settings from a JSON file and re-apply them live.
---@param path? string
local function import_settings(path)
    path = vim.fn.expand(path or DEFAULT_EXPORT)
    if vim.fn.filereadable(path) == 0 then
        vim.notify("No such file: " .. path, vim.log.levels.ERROR, { title = "Control Center" })
        return
    end
    local ok, map = pcall(vim.fn.json_decode, table.concat(vim.fn.readfile(path), "\n"))
    if not ok or type(map) ~= "table" then
        vim.notify("Invalid import file: " .. path, vim.log.levels.ERROR, { title = "Control Center" })
        return
    end
    local n = data.import_all(map)
    data.apply_saved_settings()
    vim.notify(("Imported %d settings"):format(n), vim.log.levels.INFO, { title = "Control Center" })
end

--- Resolve the group of a setting by its name (so a bare setting name can be jumped to).
---@param name string
---@return string|nil group_name, string|nil setting_name
local function group_of_setting(name)
    for _, group in ipairs(config.groups or {}) do
        for _, setting in ipairs(group.settings or {}) do
            if setting.name == name then
                return group.name, setting.name
            end
        end
    end
    return nil, nil
end

--- Register all user-facing commands and restore persisted setting values.
--- Called once during plugin setup.
function M.init()
    -- :LvimControlCenter [tab] [row]      open (optionally focused on a tab / setting)
    -- :LvimControlCenter <setting>        open focused on a setting (group resolved for you)
    -- :LvimControlCenter export [path]    export persisted settings to JSON
    -- :LvimControlCenter import [path]    import persisted settings from JSON
    vim.api.nvim_create_user_command("LvimControlCenter", function(opts)
        local a1, a2 = opts.fargs[1], opts.fargs[2]
        if a1 == "export" then
            export_settings(a2)
        elseif a1 == "import" then
            import_settings(a2)
        elseif a1 == "reset" then
            local count = data.reset(a2)
            vim.notify(
                ("Reset %d setting(s)%s"):format(count, a2 and (": " .. a2) or " to defaults"),
                vim.log.levels.INFO,
                {
                    title = "Control Center",
                }
            )
        elseif a1 and not a2 then
            -- a single arg may be a group OR a setting name — resolve a bare setting to its group.
            local g, s = group_of_setting(a1)
            if g then
                ui.open(g, s)
            else
                ui.open(a1, nil)
            end
        else
            ui.open(a1, a2)
        end
    end, {
        desc = "Open LVIM Control Center (or export/import settings)",
        nargs = "*",
        complete = function(arglead, cmdline)
            local words = vim.split(vim.trim(cmdline), "%s+")
            local cands = {}
            if #words <= 2 then
                -- first arg: special verbs + group names + every setting name (search/discovery)
                cands = { "export", "import", "reset" }
                for _, group in ipairs(config.groups or {}) do
                    cands[#cands + 1] = group.name
                    for _, setting in ipairs(group.settings or {}) do
                        cands[#cands + 1] = setting.name
                    end
                end
            else
                -- second arg: setting names within the chosen group
                for _, group in ipairs(config.groups or {}) do
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

    -- Re-apply every persisted setting so the editor state matches the saved session.
    data.apply_saved_settings()
end

return M
