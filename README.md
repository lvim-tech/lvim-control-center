# LVIM CONTROL CENTER

**`Lvim Control Center`** is an elegant and easy-to-configure settings management panel for Neovim. It provides a centralized user interface for quickly changing frequently used options, which are persisted across sessions.

[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://github.com/lvim-tech/lvim-control-center/blob/main/LICENSE)

## Features

- **Intuitive UI:** An easy-to-navigate panel with tabs (groups).
- **Jump-to-anywhere:** Instantly open the panel to a specific tab or even a specific setting by name or by row number.
- **Persistence:** Settings are automatically saved to an SQLite database and loaded on startup.
- **Easy Configuration:** Define your own settings and groups using simple Lua tables.
- **Extensibility:** Complete freedom to define complex `set` functions to manage any aspect of Neovim.
- **Multi-instance:** Spawn as many independent panels as you like — each with its own command, its own set of groups, and its **own SQLite database**. There is no global singleton (see [Multiple instances](#multiple-instances)).
- **Type Support:** Supports boolean (`bool`/`boolean`), integer (`int`/`integer`), float/number (`float`/`number`), text (`string`/`text`) and selection (`select`) options, plus `action` rows (run a callback) and `spacer` rows (visual dividers).
- **Customization:** Themed automatically from the shared lvim-utils palette; the panel size follows the shared lvim-ui geometry (`config.ui.size.float`), and highlights can be overridden per instance.

## Requirements

- Neovim >= 0.10.0
- [lvim-tech/lvim-utils](https://github.com/lvim-tech/lvim-utils) - The UI panel + config-merge layer.
- [kkharji/sqlite.lua](https://github.com/kkharji/sqlite.lua) - For settings persistence.

## Installation

Requires Neovim >= 0.10 and [lvim-utils](https://github.com/lvim-tech/lvim-utils) + [sqlite.lua](https://github.com/kkharji/sqlite.lua).

### lvim-installer (recommended)

Install and manage it from the LVIM package manager — open the **Plugins** tab and install / update / pin it:

```vim
:LvimInstaller plugins
```

lvim-installer installs plugins through Neovim's built-in `vim.pack`, so no external plugin manager is needed.

### Native (vim.pack)

```lua
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-utils" },
    { src = "https://github.com/kkharji/sqlite.lua" },
    { src = "https://github.com/lvim-tech/lvim-control-center" },
})

-- Instance-based: create an instance with a UNIQUE command (see Configuration).
require("lvim-control-center").new({
    command = "LvimControlCenter",
    groups = {}, -- you define these (see below)
})
```

## Usage

### Open the panel

```vim
:LvimControlCenter
```

By default the panel opens as a centred **float**. Pass a layout token to dock it elsewhere (order-independent with the tab / setting arguments):

```vim
:LvimControlCenter float             " centred float (default)
:LvimControlCenter area              " docked in the msgarea / cmdline (editor + statusline stay above)
:LvimControlCenter bottom            " docked as a bottom float
:LvimControlCenter bottom appearance " a layout token can be combined with a tab / setting
```

The panel size follows the **shared lvim-ui geometry** (`config.ui.size.float`) — the same geometry every lvim-ui surface reads, so resizing it once (from your own config, or a settings group you register that writes `config.ui.size`) resizes this panel too.

### Jump directly to a tab or setting!

- Open directly to a tab by name/label:
    ```vim
    :LvimControlCenter general -- name
    :LvimControlCenter General -- label
    ```
- Open directly to a setting by name (second param is setting's `name`):
    ```vim
    :LvimControlCenter lsp codelens
    ```
- Open directly to a setting by its row (as shown in the UI):

    ```vim
    :LvimControlCenter lsp 2
    ```

- You can also open from Lua (look the instance up by its command name):

    ```lua
    local cc = require("lvim-control-center")
    cc.get("LvimControlCenter"):open("lsp", "codelens") -- by name
    cc.get("LvimControlCenter"):open("lsp", 2) -- by row (number)
    ```

### Manage settings

```vim
:LvimControlCenter export [path]    " export persisted settings to JSON
:LvimControlCenter import [path]    " import settings from JSON and re-apply
:LvimControlCenter reset [setting]  " reset one setting (or all) to its default
```

A bare setting name (`:LvimControlCenter codelens`) jumps straight to it. Command-line completion offers the verbs, every group and every setting name — a quick search across the whole config.

### Navigation

- `j` / `k`: Move up/down between settings.
- `h` / `l`: Switch between tabs (groups).
- `<CR>` (Enter): Toggle / cycle / edit / execute the focused setting.
- `<Tab>` / `<BS>`: Cycle a `select` option forward / backward.
- `<Esc>`, `q`: Close the panel.

## Configuration

Create an instance with `new(opts)` (or the loader-facing `setup(opts)` — see [Multiple instances](#multiple-instances)). Every instance **requires** a unique `command` and defines its own `groups`.

### Default Configuration

These are the defaults. `command` is the only required field; pass any subset of the rest to override:

```lua
-- These are the defaults; `command` is required, everything else is optional.
require("lvim-control-center").new({
    command = "LvimControlCenter", -- REQUIRED, unique — the user command that opens this instance
    title = "LVIM CONTROL CENTER",
    title_icon = "󰒓", -- Nerd Font glyph shown before the title
    title_pos = "center", -- title alignment: "center" (default) | "left" | "right"
    -- Database directory. Omit and it is derived per command:
    -- stdpath("data")/lvim-control-center/<command> — so each instance gets its own store.
    save = "~/.local/share/nvim/lvim-control-center",
    groups = {}, -- you define these (see below)

    -- The panel SIZE is NOT set here — it follows the shared lvim-ui geometry
    -- (config.ui.size.float), so the panel resizes with that shared geometry
    -- rather than a per-plugin width/height.
    --
    -- popup_global carries the instance defaults (icons, key labels, highlight overrides).
    -- Override highlights here (see "Customizing the Appearance").
    popup_global = {
        highlights = {},
    },
})
```

`new(opts)` returns the instance, whose methods are `:open(tab?, row?, layout?)`, `:reset(name?)`, `:export(path?)`, `:import(path?)` and `:close()`. Look an instance up later with `require("lvim-control-center").get("<command>")`.

### Multiple instances

There is no global state — each `new()` is fully self-contained (own command, own database, own open-state), so you can run several side by side:

```lua
local cc = require("lvim-control-center")

-- Programmatic — the real API:
local main = cc.new({ command = "LvimControlCenter", groups = { general, appearance } })
local prefs = cc.new({ command = "MyPrefs", groups = { foo, bar } }) -- its own DB, derived from the command
main:open()

-- Declarative — the loader-facing forwarder over new(). Accepts a SINGLE instance…
require("lvim-control-center").setup({ command = "LvimControlCenter", groups = { general } })
-- …or a LIST of instances:
require("lvim-control-center").setup({
    { command = "LvimControlCenter", groups = { general, appearance } },
    { command = "MyPrefs", groups = { foo, bar } },
})
```

`setup()` holds no state of its own — it just forwards to `new()`. Called with no `command` (or an empty table) it is a quiet no-op, so a present-but-unconfigured plugin loads cleanly. `new({})` with no command raises an error.

---

### Full Configuration Example (with groups)

This is an example of how to set up two groups: "General" and "Appearance".

```lua
-- Define each settings group (one tab per group).
local general = {
    name = "general", -- internal key (used by jump-to)
    label = "General", -- tab text
    settings = {
        {
            name = "relativenumber",
            label = "Relative line numbers",
            type = "bool",
            default = false,
            get = function()
                return vim.o.relativenumber
            end,
            -- set(value, is_load, ctx): is_load is true while persisted values are applied on startup
            set = function(value)
                vim.o.relativenumber = value
            end,
        },
    },
}

local appearance = {
    name = "appearance",
    label = "Appearance",
    settings = {
        {
            name = "colorscheme",
            label = "Colorscheme",
            type = "select",
            options = { "lvim-dark", "lvim-darker", "lvim-everforest-dark", "lvim-gruvbox-dark" },
            default = "lvim-dark",
            break_load = true, -- don't re-apply on startup
            get = function()
                return vim.g.colors_name
            end,
            set = function(value)
                vim.cmd("colorscheme " .. value)
            end,
        },
        {
            name = "reload",
            label = "Reload config",
            type = "action",
            run = function(bufnr)
                vim.notify("Reloaded for buffer " .. bufnr)
            end,
        },
    },
}

require("lvim-control-center").new({
    command = "LvimControlCenter",
    groups = { general, appearance },
})
```

Each group table accepts:

| Field      | Type      | Description                                                                                                             |
| :--------- | :-------- | :-------------------------------------------------------------------------------------------------------------------- |
| `name`     | `string`  | **Required.** Unique group identifier (used by jump-to and completion).                                               |
| `label`    | `string`  | Tab text (falls back to `name`).                                                                                       |
| `icon`     | `string`  | Tab icon (trailing whitespace is stripped automatically).                                                             |
| `settings` | `table[]` | The rows in this tab (see below).                                                                                     |
| `menu`     | `boolean` | Force MENU vs FORM layout. When omitted it is auto-detected: a group whose rows are all `action`/`spacer` renders as a navigable menu; a group with value rows renders as a form. |

### Setting Definition

Each setting is a table with the following fields:

| Field     | Type                     | Description                                                                                                                                             |
| :-------- | :----------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `name`    | `string`                 | **Required.** A unique internal identifier. Often matches the option name in `vim.opt`.                                                                 |
| `label`   | `string`                 | **Required.** The name displayed in the user interface.                                                                                                 |
| `type`    | `string`                 | **Required.** The type of row: `bool`, `int`, `float`, `string`, `select`, `action`, `spacer` (aliases `boolean`/`integer`/`number`/`text` also work).  |
| `default` | `any`                    | The default value used when nothing is persisted.                                                                                                       |
| `icon`    | `string`                 | (Optional) A per-row icon.                                                                                                                              |
| `options` | `any[]`                  | (For `type="select"`) The list of possible values.                                                                                                     |
| `get`     | `function(ctx): any`     | (Optional) Returns the current live value (shown in the UI). Resolution: `get(ctx)` → persisted value → `default`.                                       |
| `set`     | `function(value, is_load, ctx)` | Called when the value changes (`is_load=false`) and once per persisted value on startup (`is_load=true`). Persist yourself with `ctx.data:save(name, value)` if the value is not derived from live editor state — it writes to THIS instance's database. |
| `run`     | `function(bufnr)`        | (For `type="action"`) Callback run when the row is activated; receives the buffer that was current when the panel opened.                                |
| `break_load` | `boolean`             | (Optional) Skip applying this setting on startup.                                                                                                       |
| `enabled` | `function(): boolean`    | (Optional) Hide the row when it returns `false` (evaluated on open) — for settings that don't apply in the current context.                             |
| `disabled` | `boolean` \| `function(value): boolean` | (Optional) Render the row dimmed + struck through (its value is unchanged). Evaluated live at render time, so it can track a parent toggle. |
| `validate` | `function(value): boolean` | (Optional) Reject a changed value when it returns `false`; it is neither applied nor persisted.                                                       |
| `desc`    | `string`                 | (Optional) A short description of the setting, forwarded to the row. Used as the label fallback when no `label` is given.                                |

#### The set function

`set` receives three arguments:

1. `value` — the new value.
2. `is_load` — `true` while a persisted value is being applied on startup, `false` on a user change. Use it to skip side effects (notifications, file writes) during restore.
3. `ctx` — the owning instance's context: `ctx.data` (persistence bound to THIS instance's database), `ctx.bufnr` (the buffer current when the panel opened), and `ctx.instance` (the instance itself). Because persistence comes from `ctx`, a group is instance-agnostic — the same group works in any instance and saves to that instance's store.

If the value is derived from live editor state (e.g. `vim.o.*`), `get`/`set` are enough — no manual persistence is needed. To persist a value across sessions, save it through `ctx.data`:

```lua
set = function(value, is_load, ctx)
    vim.o.relativenumber = value
    if not is_load and ctx and ctx.data then
        ctx.data:save("relativenumber", value)
    end
end
```

## Customizing the Appearance

The panel is rendered by [lvim-utils](https://github.com/lvim-tech/lvim-utils), so it is themed by the shared `LvimUi*` highlight groups. These self-theme from the lvim-utils palette and follow the active lvim-colorscheme automatically — normally you don't need to set anything, the panel matches the rest of the lvim-tech UI.

To override the panel's look, pass highlight overrides to the lvim-utils UI instance via `popup_global.highlights` in `new()`:

```lua
require("lvim-control-center").new({
    command = "LvimControlCenter",
    popup_global = {
        highlights = {
            -- map a panel element to an inline def or another group
            LvimUiTitle = { fg = "#89b4fa", bold = true },
            LvimUiTabActive = { bg = "#313244", fg = "#cdd6f4" },
        },
    },
})
```

| Group                                   | Description                    |
| :-------------------------------------- | :----------------------------- |
| `LvimUiNormal`                          | Panel background / normal text |
| `LvimUiBorder`                          | Panel border                   |
| `LvimUiSeparator`                       | The line under the tab bar     |
| `LvimUiTitle`                           | Panel title                    |
| `LvimUiTabActive` / `LvimUiTabInactive` | Active / inactive tab          |
| `LvimUiCursorLine`                      | The selected (active) row      |
| `LvimUiRowText*` / `LvimUiRowIcon*`     | Setting row text / icon        |
| `LvimUiFooter*`                         | The key-hint bar               |

See the [lvim-utils highlight groups](https://github.com/lvim-tech/lvim-utils#highlight-groups) for the full list.

## Tips

- You can combine jump-to-tab and jump-to-setting in your mappings, autocommands, or even via Lua for quick profile scripts!
- Both tab and setting selection are case-sensitive and work for both `name` and `label` (for tabs), and for setting `name` or row (number).

## License

This project is licensed under the BSD License. See the [LICENSE](LICENSE) file for more details.
