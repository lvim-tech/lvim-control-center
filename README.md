# LVIM CONTROL CENTER

**`Lvim Control Center`** is an elegant and easy-to-configure settings management panel for Neovim. It provides a centralized user interface for quickly changing frequently used options, which are persisted across sessions.

[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://github.com/lvim-tech/lvim-control-center/blob/main/LICENSE)

## Features

- **Intuitive UI:** An easy-to-navigate panel with tabs (groups).
- **Jump-to-anywhere:** Instantly open the panel to a specific tab or even a specific setting by name or by row number.
- **Persistence:** Settings are automatically saved to an SQLite database and loaded on startup.
- **Easy Configuration:** Define your own settings and groups using simple Lua tables.
- **Extensibility:** Complete freedom to define complex `set` functions to manage any aspect of Neovim.
- **Type Support:** Supports boolean (`bool`/`boolean`), integer (`int`/`integer`), float/number (`float`/`number`), text (`string`/`text`) and selection (`select`) options, plus `action` rows (run a callback) and `spacer` rows (visual dividers).
- **Customization:** Themed automatically from the shared lvim-utils palette; the panel size follows the shared lvim-utils geometry (edited via `:LvimUtils`), and highlights can be overridden per instance.

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

### lazy.nvim

```lua
return {
    "lvim-tech/lvim-control-center",
    dependencies = { "lvim-tech/lvim-utils", "kkharji/sqlite.lua" },
    config = function()
        require("lvim-control-center").setup({})
    end,
}
```

### packer.nvim

```lua
use({
    "lvim-tech/lvim-control-center",
    requires = { "lvim-tech/lvim-utils", "kkharji/sqlite.lua" },
    config = function()
        require("lvim-control-center").setup({})
    end,
})
```

### Native (vim.pack)

```lua
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-utils" },
    { src = "https://github.com/kkharji/sqlite.lua" },
    { src = "https://github.com/lvim-tech/lvim-control-center" },
})
require("lvim-control-center").setup({})
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

The panel size follows the **shared lvim-utils geometry** (`config.ui.size.float`, edited via `:LvimUtils` or the "Utils" tab) — resize it there once and every lvim-utils panel, including this one, tracks it.

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

- You can also open from Lua:

    ```lua
    require("lvim-control-center.ui").open("lsp", "codelens") -- by name
    require("lvim-control-center.ui").open("lsp", 2) -- by row (number)
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

The configuration is passed to the `setup()` function. The most important part is defining the `groups`.

### Default Configuration

This is the default configuration. You can override any of these fields in your own setup:

```lua
-- These are the defaults; pass any subset to override.
require("lvim-control-center").setup({
    title = "LVIM CONTROL CENTER",
    title_pos = "center", -- title alignment: "center" (default) | "left" | "right"
    save = "~/.local/share/nvim/lvim-control-center",
    groups = {}, -- you define these (see below)

    -- The panel SIZE is NOT set here — it follows the shared lvim-utils geometry
    -- (config.ui.size.float, edited via :LvimUtils / the "Utils" tab), so the panel
    -- resizes with those settings rather than a per-plugin width/height.
    --
    -- popup_global carries the instance defaults (icons, key labels, highlight overrides).
    -- Override highlights here (see "Customizing the Appearance").
    popup_global = {
        highlights = {},
    },
})
```

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
            -- set(value, is_load, bufnr): is_load is true while persisted values are applied on startup
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

require("lvim-control-center").setup({
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
| `get`     | `function(): any`        | (Optional) Returns the current live value (shown in the UI). Resolution: `get()` → persisted value → `default`.                                         |
| `set`     | `function(value, is_load, bufnr?)` | Called when the value changes (`is_load=false`) and once per persisted value on startup (`is_load=true`). Persist yourself with `require("lvim-control-center.persistence.data").save(name, value)` if the value is not derived from live editor state. |
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
3. `bufnr` — the buffer that was current when the panel opened.

If the value is derived from live editor state (e.g. `vim.o.*`), `get`/`set` are enough — no manual persistence is needed. To persist a value across sessions, save it yourself:

```lua
local data = require("lvim-control-center.persistence.data")

set = function(value, is_load)
    vim.o.relativenumber = value
    if not is_load then
        data.save("relativenumber", value)
    end
end
```

## Customizing the Appearance

The panel is rendered by [lvim-utils](https://github.com/lvim-tech/lvim-utils), so it is themed by the shared `LvimUi*` highlight groups. These self-theme from the lvim-utils palette and follow the active lvim-colorscheme automatically — normally you don't need to set anything, the panel matches the rest of the lvim-tech UI.

To override the panel's look, pass highlight overrides to the lvim-utils UI instance via `popup_global.highlights` in `setup()`:

```lua
require("lvim-control-center").setup({
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
