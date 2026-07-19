# Changelog

## Unreleased

## 1.4.7 - 2026-07-19

### Changes

- The main GearPolice window can now be closed with the Escape key.

## 1.4.6 - 2026-07-12

### Changes

- The player list is now displayed alphabetically.

## 1.4.5 - 2026-07-10

### Changes

- Automatic report-offer whispers are now disabled in battlegrounds and arenas.

## 1.4.4 - 2026-07-10

### Features

- Added separate settings for automatic report offers in parties and raids.
- Low item level reports now show the configured threshold.

### Fixes

- Fixed off-hand scanning for characters who can dual-wield two-handed weapons.
- Empty weapon slots no longer keep scans waiting for item data.
- Unfinished target scans now stop when you change targets.
- The group list now initializes correctly after login or reload.
- Retrying scans now show a consistent scanning status.

## 1.4.3 - 2026-07-10

### Fixes

- Fixed automatic report-offer coordination in parties when Raid Only is enabled.
- Improved the reliability of report-offer coordination between group members.
- `/gearpolice scan` now clears the current list and performs a fresh group scan.
- The selected player-list filter is now remembered automatically.

## 1.4.2 - 2026-07-03

### Features

- Added a setting to control whether GearPolice announces when Manual Report Mode is changed to Public.

## 1.4.1 - 2026-06-28

### Features

- Added an Auto-Whisper In Raid Only setting for automatic report offers.

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
