# BabonyaPlates

A nameplate addon for WoW Forever (Interface 16001): choose per unit type whether you see names and health bars, and restyle the bars.

## Features

- Name / bar / power toggles for enemy and friendly players, party & raid, guild, hostile / neutral / friendly NPCs, pets & totems, critters
- Quest mobs always shown, with a quest icon
- Keybind (or `/bpt toggle`) to hide all bars while keeping names
- HP text as percent, value or both, with optional max
- Colors, class colors, textures, borders and fonts (LibSharedMedia)
- Combo points on your target, raid markers, target highlight
- Cast bars (shield colour for uninterruptible casts), shown per unit type even on name-only plates
- Auras: all debuffs, with your own debuffs and purgeable enemy buffs larger and outlined
- Threat colours (tank or DPS, auto-detected from stance/form), execute colour below a health threshold, absorb shields
- Elite / rare / boss icon and difficulty-coloured level
- "Bars only in combat" per unit type
- Profile import / export strings
- Layout editor with drag and drop (`/bpt edit`), profiles

## Installation

1. Copy the `BabonyaPlates` folder into `_forever_/Interface/AddOns`, or symlink it there.
2. Disable other nameplate addons (ThreatPlates, Plater, ...) and Questie's nameplate icons.
3. Start the game (or run `/reload` if already in game).

## Usage

- `/bpt` or `/babonyaplates` opens the settings (also under Options → AddOns)
- `/bpt edit` opens the layout editor
- `/bpt toggle` hides or shows all bars; bind a key under Key Bindings → AddOns → BabonyaPlates

## Libraries

Embedded in `Libs/`, each under its own license: Ace3 incl. AceSerializer (see `Libs/Ace3-LICENSE.txt`), LibSharedMedia-3.0, AceGUI-3.0-SharedMediaWidgets.
