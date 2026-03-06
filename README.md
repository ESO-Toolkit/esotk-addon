# ESOTK

Official ESOTK addon for Elder Scrolls Online.

## Features

- **Modular architecture** — each feature lives in its own file under the `ESOtk` namespace
- **Slash command router** — `/esotk <command>` dispatches to the appropriate module
- **Roster validation** — import rosters and validate group members against them

## Slash Commands

| Command | Description |
|---------|-------------|
| `/esotk help` | Show available commands |
| `/esotk group` | Print current group info |
| `/esotk roster` | Roster import / management |
| `/esotk validate` | Run roster validation |
| `/esotk gear` | Print local player gear |

## File Structure

```
ESOtk/
  ESOtk.txt              -- Manifest (load order)
  Util.lua                -- Shared utilities (Base64, string helpers)
  GroupScanner.lua        -- Group member scanning
  RosterImport.lua        -- Roster data import/storage
  RosterValidator.lua     -- Validation engine
  GearScanner.lua         -- Local player gear scanning
  ValidationUI.lua        -- Chat output formatting
  ESOtk.lua               -- Main entry point, init, slash commands
```

## Installation

1. Download the latest release from the [Releases](../../releases) page.
2. Extract the `ESOtk` folder into your ESO AddOns directory:
   ```
   Documents\Elder Scrolls Online\live\AddOns\
   ```
3. Launch ESO and enable **ESOtk** in the AddOns menu.

## Requirements

- Elder Scrolls Online (latest patch)

## Development

Clone the repo directly into your AddOns directory, or symlink it there:

```powershell
git clone https://github.com/ESO-Toolkit/esotk-addon.git "ESOtk"
```

### Module Development

Each module attaches to the `ESOtk` global namespace:

```lua
ESOtk = ESOtk or {}
ESOtk.MyModule = {}

local MyModule = ESOtk.MyModule

function MyModule.DoSomething()
    ESOtk.Util.Print("Hello from MyModule!")
end
```

Add new files to `ESOtk.txt` in the correct load order (utilities first, main entry point last).

## License

MIT
