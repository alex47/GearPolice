# AGENTS.md

## Project Context

- GearPolice is a World of Warcraft MoP Classic addon written for Lua 5.1.
- There is no build step. The addon is loaded directly from `GearPolice.toc`.
- Keep `GearPolice.toc` load order explicit. When adding Lua/XML files, add them to the TOC after their dependencies and before callers.
- Do not edit files under `Libs/` unless the task is explicitly to update bundled libraries.
- Keep addon-facing branding as `GearPolice`.
- Keep `CHANGELOG.md` user-facing: describe changes in plain player-facing language and avoid implementation details that only developers care about.
- Version numbers are release-based and increase only once per tag. After a version is selected for an upcoming release, keep all commits for that release on the same version until it is tagged; do not bump the version for each code change or commit.
- After a release is tagged, select and apply the next version only when beginning or preparing the next tagged release.
- Keep `CHANGELOG.md` updated for the current unreleased/tagged version unless the user explicitly says a change should not be listed.

## Architecture

- `Core.lua` should stay focused on addon bootstrap, event registration, slash commands, and high-level routing.
- `Config/` owns constants, slot order, and rule configuration.
- `State/` owns runtime state and saved player records.
- `State/Problems.lua` is the canonical owner of structured gear issue records and derived problem indexes.
- `Services/` owns settings, timers, roster reconciliation, scan queue, scan session, peer communication, automatic-message lifecycle, report offers, automatic scan announcements, and outbound chat throttling.
- `Inspection/` owns item checks, slot resolution, and running configured checks.
- `UI/` owns view models, windows, rows, widgets, minimap UI, and help text.
- `Reporting.lua` owns report message formatting and delivery.
- `Helper.lua` is a compatibility namespace for older `GearPolice.Helper` callers.

## Coding Rules

- Use Lua 5.1-compatible syntax and APIs. Do not use newer Lua features.
- Prefer existing Ace3, WoW API, and local helper patterns over new abstractions.
- Keep saved-variable changes explicit. Do not add migrations unless the user asks for one.
- Keep scan behavior completion-driven. Timers may wait or retry, but must not be the authority for scan completion.
- Every async scan, retry, inspect-ready, and slot callback must validate the current scan generation before writing state.
- A successful scan must leave no queued duplicate and no player-owned retry timer that can move that player back to scanning.
- Group scans should retry only while the player is still in the group. Target scans should retry only while the current target still matches the requested player.
- Target scans only apply to player targets.
- Use structured problem records when touching item issue handling: `slotName`, `itemLink`, `ruleId`, and `message`.
- Route player-facing report text through `Reporting.lua` so the `{Square} GearPolice {Cross}` prefix and message style stay unified.
- Route addon-owned outgoing chat through `Services/ChatThrottle.lua`. Do not call `SendChatMessage` directly for reports, report offers, or automatic scan summaries.
- Automatic report-offer whispers and automatic scan summaries must remain disabled inside battlegrounds and arenas; manual reports and explicit `!gp` replies remain available.
- Keep `!gp` as the documented whisper request trigger. The hidden `|gp` compatibility trigger should not be mentioned in player help unless requested.

## UI Rules

- The main window should stay operational and direct, not a landing page.
- Keep report mode, automatic announcements, report offers, hide-whisper options, check toggles, and minimap visibility in the generated AceConfig settings page.
- Keep the minimap right-click menu focused on opening the main window, Settings, Help, and Close.
- Keep row item tooltips using Blizzard item hyperlinks unchanged, then append GearPolice issue lines below them.
- Do not prefix item names in tooltips with slot names.
- Always review `UI/HelpWindow.lua` when functionality changes. Update the help text for any player-visible behavior, option, command, report flow, scan behavior, or UI interaction that changed.

## Validation

Run these checks after Lua/XML changes:

```sh
luac5.1 -p Libs/AceComm-3.0/ChatThrottleLib.lua Libs/AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua Libs/AceConfig-3.0/AceConfigCmd-3.0/AceConfigCmd-3.0.lua Libs/AceConfig-3.0/AceConfigDialog-3.0/AceConfigDialog-3.0.lua Libs/AceConfig-3.0/AceConfig-3.0.lua Core.lua Debug.lua Helper.lua Inspection.lua Reporting.lua UI.lua Config/Constants.lua Config/Slots.lua Config/Rules.lua Util/Tables.lua Util/Units.lua Util/Players.lua Util/Inventory.lua State/RuntimeState.lua State/PlayerStore.lua State/Problems.lua Services/Timers.lua Services/Settings.lua Services/Roster.lua Services/ScanQueue.lua Services/ScanSession.lua Services/Comms.lua Services/AutomaticMessageFlow.lua Services/PublicAnnouncements.lua Services/ReportOffers.lua Services/ChatThrottle.lua Inspection/ItemChecks.lua Inspection/SlotResolver.lua Inspection/CheckRunner.lua UI/ViewModel.lua UI/Widgets/ItemIcon.lua UI/PlayerRows.lua UI/MainWindow.lua UI/HelpWindow.lua UI/AceConfigOptions.lua UI/MinimapMenu.lua UI/MinimapIcon.lua
git diff --check
luacheck . --exclude-files Libs
```

Expected lint state: `0 warnings / 0 errors`.

## Manual Smoke Tests

When behavior changes, mention which of these need in-game validation:

- Group scan includes the local player and follows current party/raid order.
- Players leaving the group are removed and their active work is cancelled.
- Leaving the group clears rows, queue, current scan, and timers.
- Target scan clears old target item data and scans only player targets.
- Completed scans do not revert from green/done to scanning.
- Partial scans retry later without affecting later successful scans.
- Debug report and whisper/announcement reports still show full item links.
- Report offers include deterministic per-issue counts and respect the UI toggle, 12-hour cooldown, combat delay,
  and hide-whisper setting.
- When multiple GearPolice users enable Report Offers, only the elected coordinator sends automatic offers.
- Automatic scan summaries announce only successful grouped players with issues, include deterministic per-issue counts, respect party/raid scope and the 12-hour cooldown, and use one elected announcer.
- Minimap left-click toggles the main window and right-click opens the menu.
