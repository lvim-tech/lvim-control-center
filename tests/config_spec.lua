-- The config template, and the one indirection that already cost this plugin rows.
--
-- There is no single live config table here: `defaults()` returns a FRESH one each call so two
-- instances never share state, and a group may declare its settings as a LIST or as a FUNCTION
-- returning one. The function form exists for a measured reason, written into the type
-- annotation: a group module describing ANOTHER plugin is required while this one loads, which
-- can be before that plugin exists -- a list built then is built from nothing and stays empty
-- forever, and the appearance tab showed 2 rows instead of 16.
--
-- The panel itself needs sqlite.lua, a declared dependency that is not installed here, so
-- `instance` cannot even be required; those cases skip and name it.

local config = require("lvim-control-center.config")

describe("lvim-control-center: the default template")

it("every call hands back a table of its own", function()
    local a, b = config.defaults(), config.defaults()
    truthy(a ~= b, "two instances must not share one config table")

    a.groups[#a.groups + 1] = { name = "mine" }
    a.title = "changed"
    eq(0, #b.groups, "mutating one instance's config reached the other's")
    truthy(b.title ~= "changed")
end)

it("the template carries the fields an instance is built from", function()
    local d = config.defaults()
    eq(nil, d.command, "the command is REQUIRED per instance, so the template cannot supply one")
    eq(true, d.register_command, "a command is registered unless the host says otherwise")
    eq({}, d.groups)
    eq({}, d.subcommands)
    eq(nil, d.save, "the database directory is derived from the command when it is not given")
    truthy(type(d.popup_global) == "table", "passed verbatim to lvim-ui.new()")
end)

it("the template does not set the panel's size", function()
    -- The size comes from the central geometry authority (lvim-utils dock geometry), so a size
    -- here would be a second source of truth that silently wins.
    local d = config.defaults()
    eq(nil, d.width)
    eq(nil, d.height)
end)

describe("lvim-control-center: a group's settings, list or function")

it("a list is returned as it is", function()
    local list = { { name = "a" }, { name = "b" } }
    eq(list, config.settings_of({ settings = list }))
end)

it("a function is called, and its list used", function()
    local calls = 0
    local group = {
        settings = function()
            calls = calls + 1
            return { { name = "built later" } }
        end,
    }
    eq(1, #config.settings_of(group))
    eq(1, calls)
    eq(1, #config.settings_of(group))
    eq(2, calls, "it is resolved at every use, which is the whole point of the function form")
end)

it("a function that raises costs that group its rows and nothing else", function()
    eq(
        {},
        config.settings_of({
            settings = function()
                error("the other plugin is not there yet")
            end,
        }),
        "a table, so the caller can iterate the result directly"
    )
end)

it("a function that answers with something that is not a list is ignored", function()
    eq(
        {},
        config.settings_of({
            settings = function()
                return 42
            end,
        })
    )
end)

it("a group with no settings is an empty list, never nil", function()
    eq({}, config.settings_of({}))
    eq({}, config.settings_of(nil))
end)

describe("lvim-control-center: the panel")

it("the instance module needs sqlite.lua", function()
    local ok, mod = pcall(require, "lvim-control-center.instance")
    if not ok then
        skip("building an instance", "sqlite.lua is a declared dependency and is not installed here")
        return
    end

    -- With sqlite present: a command is required, and two instances keep their own config.
    truthy(type(mod.new) == "function")
    eq(false, (pcall(mod.new, { register_command = false })), "an instance without a command has no key")

    local a = mod.new({ command = "LvimCcSpecA", register_command = false, groups = {} })
    local b = mod.new({ command = "LvimCcSpecB", register_command = false, groups = {} })
    truthy(a.config ~= b.config, "each instance owns its config")
    eq("LvimCcSpecA", a.config.command)
    eq("LvimCcSpecB", b.config.command)
end)
