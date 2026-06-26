# Changelog

## Unreleased

### Features

- Coordinates automatic report offers between GearPolice users in the same party or raid so only one enabled sender whispers each player.

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
