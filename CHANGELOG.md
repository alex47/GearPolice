# Changelog

## Unreleased

## 1.4.0 - 2026-06-27

### Features

- Added a GearPolice page to the game's AddOns settings.
- Added settings for enabled gear checks and the low item level threshold.
- Added a Help window with addon version and author information.
- If multiple GearPolice users have auto-whispers enabled in the same group, GearPolice now chooses one sender so players do not receive duplicate offer whispers.

### Fixes

- Opening Settings now closes the main GearPolice window.
- Public report mode now announces itself only while you are in a group.
- Long reports are now split into safe chat-sized messages.
- Improved main-window toolbar alignment and button labels.

## 1.3.0 - 2026-06-26

Initial CurseForge release.

### Features

- Scans party and raid members, including the local player.
- Supports target scans for player targets outside the group.
- Checks equipped items for missing gems, missing enchants, missing upgrades, low item level, extra waist gem issues, and enchanter ring enchant cases.
- Shows scan status, item icons, and GearPolice issue lines in item tooltips.
- Supports whisper, public, and debug report modes.
- Adds optional report offers so players can whisper `!gp` to receive their own report.
- Adds a minimap button with quick access to the main window, options, and help.
- Routes outgoing report messages through ChatThrottleLib-based throttling.

### Notes

- Designed for World of Warcraft MoP Classic.
- Other players do not need to install GearPolice to receive reports.
