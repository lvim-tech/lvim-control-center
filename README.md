# LVIM CONTROL CENTER

[License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)(https://opensource.org/licenses/MIT)

**`Lvim Control Center`** is an elegant and easy-to-configure settings management panel for Neovim. It provides a centralized user interface for quickly changing frequently used options, which are persisted across sessions.

## ✨ Features

- **Intuitive UI:** An easy-to-navigate panel with tabs (groups).
- **Jump-to-anywhere:** Instantly open the panel to a specific tab or even a specific setting by name or by row number.
- **Persistence:** Settings are automatically saved to an SQLite database and loaded on startup.
- **Easy Configuration:** Define your own settings and groups using simple Lua tables.
- **Extensibility:** Complete freedom to define complex `set` functions to manage any aspect of Neovim.
- **Type Support:** Supports boolean (`bool`/`boolean`), integer (`int`/`integer`), float/number (`float`/`number`), text (`string`/`text`), and selection (`select`) options.
- **Customization:** Easily change the appearance, such as window size, borders, dimensions, and colors.

## 📋 Requirements

- Neovim >= 0.10.0
- [kkharji/sqlite.lua](https://github.com/kkharji/sqlite.lua) - For settings persistence.

## 💾 Installation

### LVIM IDE

Ships with LVIM IDE. Override its options in your user module
(`lua/modules/user/init.lua`):

```lua
modules["lvim-tech/lvim-control-center"] = {
    dependencies = { "lvim-tech/lvim-utils", "kkharji/sqlite.lua" },
    opts = { ... },
}
```

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

### Native (vim.pack / packadd)

```lua
-- In your init.lua, after the plugin is on the runtimepath:
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-utils" },
    { src = "https://github.com/kkharji/sqlite.lua" },
    { src = "https://github.com/lvim-tech/lvim-control-center" },
})

require("lvim-control-center").setup({})
```

### packer.nvim

```lua
use({
    "lvim-tech/lvim-control-center",
    requires = { "lvim-tech/lvim-utils", "kkharji/sqlite.lua" },
    config = function()
        require("lvim-control-center").setup({ ... })
    end,
})
```

## 🚀 Usage

### Open the panel

```vim
:LvimControlCenter
```

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
- `<CR>` (Enter): Change the selected setting.
- `<BS>`: Cycle select settings backward.
- `<Esc>`, `q`: Close the panel.

## ⚙️ Configuration

The configuration is passed to the `setup()` function. The most important part is defining the `groups`.

### Default Configuration

This is the default configuration. You can override any of these fields in your own setup:

```lua
-- These are the defaults; pass any subset to override.
require("lvim-control-center").setup({
    title = "LVIM CONTROL CENTER",
    save = "~/.local/share/nvim/lvim-control-center",
    groups = {}, -- you define these (see below)

    -- Forwarded verbatim to require("lvim-utils.ui").new(): popup geometry, icons, keys,
    -- labels and highlight overrides. See lvim-utils for the full list of options + defaults.
    popup_global = {
        position = "editor",
        width = 0.8,
        max_width = 0.8,
        height = "auto",
        max_height = 0.8,
        max_items = 15,
        close_keys = { "q", "<Esc>" },
        keys = {
            down = "j",
            up = "k",
            confirm = "<CR>",
            cancel = "<Esc>",
            close = "q",
            tabs = { next = "l", prev = "h" },
        },
        -- Empty by default — the panel uses the shared LvimUi* groups (self-themed from the
        -- lvim-utils palette). Override them here (see "Customizing the Appearance").
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
    popup_global = {
        width = 0.6, -- override any popup_global option here
    },
})
```

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
| `validate` | `function(value): boolean` | (Optional) Reject a changed value when it returns `false`; it is neither applied nor persisted.                                                       |
| `desc`    | `string`                 | (Optional) Shown live as a help line (the panel subtitle) for the focused setting.                                                                      |

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

## 🎨 Customizing the Appearance

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

## 🏃 Tips

- You can combine jump-to-tab and jump-to-setting in your mappings, autocommands, or even via Lua for quick profile scripts!
- Both tab and setting selection are case-sensitive and work for both `name` and `label` (for tabs), and for setting `name` or row (number).

## 📄 License

This project is licensed under the BSD License. See the [LICENSE](LICENSE) file for more details.
