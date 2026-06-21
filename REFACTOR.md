# GearPolice Refactor Plan

This document is the long-term organization plan for GearPolice. The goal is not
to rewrite the addon in one pass. The goal is to split responsibilities
incrementally while preserving the inspect behavior that has already been
stabilized.

## Goals

- Make ownership of scan state, roster state, timers, inspection rules, and UI
  rendering obvious from file names and module boundaries.
- Keep the scan lifecycle completion-driven: a player that reached a terminal
  state must not be moved back to scanning by stale queue, timer, or inspect
  callbacks.
- Make future features easier, especially showing problem details in the UI,
  adding/removing rules, and changing roster behavior.
- Reduce the size and responsibility count of `Core.lua`.
- Preserve behavior through small, verifiable extraction steps.

## Progress

- Complete: Phase 1, extract constants and slots.
- Complete: Phase 2, extract rule configuration from `Inspection:CheckUnit`.
- Complete: Phase 3, extract timer service.
- Complete: Phase 4, extract player store.
- Complete: Phase 5, extract roster service.
- Complete: Phase 6, extract scan queue.
- Next: Phase 7, extract scan session.

## Non-Goals

- Do not rewrite every subsystem at once.
- Do not change saved variables unless a specific migration is planned.
- Do not change gameplay behavior as part of pure file movement.
- Do not refactor Ace3 libraries or vendored files under `Libs/`.
- Do not introduce a build step; this should remain a normal WoW addon loaded by
  the `.toc`.

## Current Shape

Current top-level addon files:

```text
Core.lua        -- addon bootstrap plus most runtime behavior
Inspection.lua  -- slot resolution, item checks, slot rule config, check runner
UI.lua          -- custom item icon widget, window creation, row rendering
Helper.lua      -- inventory and unit lookup helpers
Reporting.lua   -- report formatting and delivery
Debug.lua       -- debug print helpers
```

The main maintenance issue is `Core.lua`. It currently owns:

- addon initialization
- event registration
- slash command handling
- runtime timer ownership
- scan queue storage and dispatch
- active scan/session lifecycle
- inspect-ready timeout and retry behavior
- player record creation and reset
- roster snapshot creation
- roster reconciliation
- ordered player display list
- target scan behavior
- group scan behavior

`Inspection.lua` is more cohesive, but still combines:

- slot-state storage helpers
- empty-slot confirmation
- item metadata pending handling
- individual item checks
- check definitions
- slot-to-rule configuration
- slot resolution with retry
- scan-local completion tracking

`UI.lua` combines:

- the custom `GearPoliceItemIcon` widget
- main window creation
- row cache/rebuild logic
- player row creation
- player row updating
- item tooltip setup
- UI-specific status texture mapping

## Target Folder Layout

This is the desired end-state shape. It can be reached gradually.

```text
GearPolice.toc
embeds.xml

Core.lua

Config/
  Constants.lua
  Slots.lua
  Rules.lua

State/
  PlayerStore.lua
  RuntimeState.lua

Services/
  Timers.lua
  Roster.lua
  ScanQueue.lua
  ScanSession.lua

Inspection/
  SlotResolver.lua
  ItemChecks.lua
  CheckRunner.lua

UI/
  Widgets/
    ItemIcon.lua
  ViewModel.lua
  MainWindow.lua
  PlayerRows.lua

Util/
  Units.lua
  Inventory.lua
  Tables.lua

Reporting.lua
Debug.lua
```

The `.toc` load order should remain explicit. Load lower-level modules before
higher-level modules:

```text
embeds.xml
Core.lua
Config/Constants.lua
Config/Slots.lua
Config/Rules.lua
Util/Tables.lua
Util/Units.lua
Util/Inventory.lua
State/RuntimeState.lua
State/PlayerStore.lua
Services/Timers.lua
Services/Roster.lua
Services/ScanQueue.lua
Services/ScanSession.lua
Inspection/ItemChecks.lua
Inspection/SlotResolver.lua
Inspection/CheckRunner.lua
UI/Widgets/ItemIcon.lua
UI/ViewModel.lua
UI/PlayerRows.lua
UI/MainWindow.lua
Reporting.lua
Debug.lua
```

The exact order can change during implementation, but dependencies should only
flow downward where practical:

- config/util modules should not call service/UI modules
- inspection modules should not call UI modules
- UI modules should render already-prepared state instead of deciding scan policy
- reporting should consume structured problem data, not inspect raw scan internals

## Module Responsibilities

### Core.lua

Keep `Core.lua` as the addon bootstrap and router.

Responsibilities:

- create the AceAddon instance
- initialize AceDB
- initialize runtime state
- register events
- register slash commands
- delegate event and command work to focused modules

It should eventually not contain scan queue logic, roster reconciliation, timer
ownership, item inspection, UI row rendering, or player record mutation helpers.

### Config/Constants.lua

Own addon-wide constants and sentinel values.

Examples:

- `InventorySlotReady`
- `InventorySlotPending`
- `InventorySlotNoEvidence`
- `InventorySlotEmpty`
- `ItemMetadataPending`
- retry counts and retry delays
- empty-slot confirmation thresholds
- scan status strings
- report mode strings
- common texture paths
- item level threshold

Reasoning:

These values are currently spread through `Core.lua`, `Inspection.lua`, and
`UI.lua`. Keeping them in one place makes status mapping and future tuning safer.

### Config/Slots.lua

Own equipment slot order and slot groups.

Examples:

- display/scan slot order
- inventory snapshot evidence slots
- slots that can have enchants
- slots that can have gems
- weapon/offhand special handling metadata

Reasoning:

Slot order is currently in `Helper.lua`, while slot rule config is inside
`Inspection:CheckUnit`. Those are related concerns and should be easier to audit
together.

### Config/Rules.lua

Own rule definitions and slot-to-rule configuration.

Target shape:

```lua
GearPolice.Rules = {
    missing_gems = {
        id = "missing_gems",
        message = "Missing Gem",
        evaluate = function(itemLink, context)
            return GearPolice.ItemChecks:IsItemMissingGems(itemLink, context)
        end,
    },
}

GearPolice.SlotRules = {
    HeadSlot = { "missing_gems", "low_item_level", "missing_upgrade" },
    ChestSlot = { "missing_gems", "missing_enchant", "low_item_level", "missing_upgrade" },
}
```

Reasoning:

Rules are currently created inside every `Inspection:CheckUnit` call. Moving them
to config makes rule changes easier, avoids recreating static tables per scan,
and gives the UI/reporting code stable rule IDs.

### State/RuntimeState.lua

Own unsaved runtime tables.

Examples:

- scan queue
- queued scan reasons
- current scan/session
- active timers
- player-owned timers
- current roster snapshot
- grouped/un-grouped transition flag

Reasoning:

Runtime state is currently stored directly on `GearPolice` from `Core.lua`. That
works, but makes it hard to distinguish saved player data from transient scan
machinery.

### State/PlayerStore.lua

Own player record creation, reset, and mutation helpers.

Responsibilities:

- create a default player record
- reset a player for a forced target scan
- clear all tracked players
- remove one player from tracking
- normalize old/malformed saved data if needed
- expose helpers such as `GetPlayerInfo`, `EnsurePlayer`, and `UpdatePlayerName`

Current functions that belong here:

- `SetPlayerGuidToDefaultInPlayerGearInfo`
- `ResetPlayerGearInfo`
- parts of `ClearAllTrackedPlayers`
- parts of `RemovePlayerFromTracking`

Reasoning:

Player record shape should have one owner. Right now several systems write fields
directly into `PlayerGearInfo`.

### Services/Timers.lua

Own managed timer scheduling and cancellation.

Current functions that belong here:

- `ScheduleManagedTimer`
- `CancelManagedTimersForPlayer`
- `CancelAllManagedTimers`
- `CancelScanQueueTimer`, or move this to `ScanQueue` if it remains queue-only

Rules:

- every scheduled retry/follow-up should be owned by either a player GUID or a
  named global purpose
- player removal must cancel all player-owned timers
- `StopAllScans` must cancel all managed timers

Reasoning:

Timers were a source of stale state bugs. Keeping ownership explicit is more
important than reducing lines of code.

### Services/Roster.lua

Own roster snapshots and reconciliation.

Current functions that belong here:

- `CreateEmptyRosterSnapshot`
- `ResetRosterSnapshot`
- `BuildGroupRosterSnapshot`
- `RefreshCurrentRosterSnapshot`
- `ApplyRosterMetadata`
- `ClearRosterMetadata`
- `RemoveGuidFromCurrentRoster`
- `ReconcileGroupRoster`
- `UpdatePlayerGearInfoWithGroupMembers`
- `ProcessGroupMember`

Rules:

- build a fresh snapshot on `GROUP_ROSTER_UPDATE`
- clear all tracked players when going from groupless to grouped
- clear all tracked players when leaving the group
- remove roster-tracked players that leave the group
- keep target-only entries while grouped unless the local player leaves the group
- keep ordering based on current `raidN`/`partyN`
- include the local player in party and raid snapshots when appropriate

Reasoning:

Roster behavior has many edge cases but little direct relationship to item
checks. It deserves its own module.

### Services/ScanQueue.lua

Own the queue of scan requests.

Responsibilities:

- add a player to the queue
- de-duplicate queued players
- move target scans to the front when requested
- remove a player from the queue
- skip already-complete players unless forced
- dispatch exactly one active scan when no scan is active
- pause dispatch during combat
- schedule a small throttle before dispatching the next queued scan

Current functions that belong here:

- `NormalizeScanReason`
- `IsPlayerQueued`
- `AddToScanQueue`
- `RemoveFromScanQueue`
- `ScheduleScanQueueProcessing`
- `ProcessScanQueue`, after scan-session parts are separated
- `OnCombatEnded`, or a small event handler that delegates here

Important invariant:

The queue only starts scans. It must not decide that a scan is complete. Scan
completion must continue to happen through the active scan/session terminal path.

### Services/ScanSession.lua

Own one active inspect flow.

Responsibilities:

- start inspection of a unit
- store current scan identity: player GUID, unit ID, reason, generation
- handle `INSPECT_READY`
- handle inspect-ready timeout
- retry `CanInspect`/unit availability
- run inspection checks
- finish scans through one terminal path
- schedule delayed follow-up scans for `Partial` or `TemporaryFailed`
- clear current scan for removed players or combat pause

Current functions that belong here:

- `IsCurrentScan`
- `IsScanTargetAvailable`
- `GetScanUnitId`
- `IsLocalPlayerGuid`
- `FinishScan`
- `ScheduleDelayedScanRetry`
- `ScheduleInspectReadyTimeout`
- `RunInspectionChecks`
- `StartInspectionOfUnit`
- `RetryInspection`
- `ClearCurrentScanForPlayer`
- parts of `ClearScheduledWorkForPlayer`

Important invariants:

- every scan has a generation created before `NotifyInspect`
- every async callback validates the generation
- every terminal scan path goes through `FinishScan`
- `Successful` scans must leave no queued copy and no player-owned timer
- stale callbacks must no-op without changing UI-visible status

### Inspection/SlotResolver.lua

Own slot resolution only.

Responsibilities:

- ask WoW APIs for slot state
- retry pending slots
- confirm empty slots using evidence
- write `READY`, `EMPTY`, or `PENDING` slot results
- never run gem/enchant/ilevel/upgrade checks

Current functions that belong here:

- `ResolveInventorySlotWithRetry`
- `SetEquippedSlotValue`
- `GetCapturedInventoryEvidenceCount`
- `CanConfirmEmptyInventorySlot`
- `IsStoredItemLink`, or move this to `Util/Inventory.lua`

Reasoning:

Slot resolution is timing-sensitive. Keeping it separate from rule evaluation
makes retry bugs easier to isolate.

### Inspection/ItemChecks.lua

Own individual item rule functions.

Current functions that belong here:

- `IsItemInfoAvailable`
- `CountSocketSlots`
- `CountSocketedGemIds`
- `IsItemMissingGems`
- `IsItemMissingEnchant`
- `IsItemBelowItemLevel`
- `IsWaistMissingExtraGemEnchant`
- `IsItemMissingUpgrade`
- `IsTwoHandedOrRangedWeaponLink`

Reasoning:

These functions are mostly pure item-link logic. They should be easy to test
with `/run` snippets or small Lua harnesses where possible.

### Inspection/CheckRunner.lua

Own scan-local slot scheduling and rule application.

Current functions that belong here:

- `ApplySlotChecks`
- `CheckUnit`

Responsibilities:

- reset scan-local result fields
- resolve `MainHandSlot` first
- skip offhand when main hand is two-handed/ranged
- schedule one resolver per slot
- apply configured rules after each slot resolves
- call `onComplete` exactly once

Reasoning:

This module is the bridge between slot resolving and rule checks. It should not
own retry timers directly except through `SlotResolver`.

### UI/Widgets/ItemIcon.lua

Own the custom `GearPoliceItemIcon` AceGUI widget.

Responsibilities:

- image texture
- image sizing
- hover/click callback forwarding
- problematic border state
- lifecycle reset on acquire/release

Reasoning:

The custom widget fixed pooled AceGUI styling leakage. It should be isolated from
main UI rendering logic.

### UI/ViewModel.lua

Convert addon state into simple render data.

Target row shape:

```lua
{
    playerGuid = "...",
    playerName = "Name",
    status = "Successful",
    statusTexture = "Interface\\RaidFrame\\ReadyCheck-Ready",
    hasProblems = true,
    slots = {
        {
            slotName = "ChestSlot",
            state = "item",
            itemLink = "...",
            texture = "...",
            problems = {
                { ruleId = "missing_gems", message = "Missing Gem" },
            },
        },
        {
            slotName = "SecondaryHandSlot",
            state = "empty",
        },
        {
            slotName = "HeadSlot",
            state = "pending",
        },
    },
}
```

Reasoning:

The UI should not need to know all raw fields in `PlayerGearInfo`. A view model
makes rendering predictable and enables the later feature to show exact problem
details in the UI.

### UI/MainWindow.lua

Own frame creation and top-level controls.

Responsibilities:

- main AceGUI frame
- Clear button
- Refresh button
- Target button
- report mode dropdown
- scroll container
- open/close lifecycle

### UI/PlayerRows.lua

Own player row creation and updates.

Responsibilities:

- row cache
- row rebuild when order changes
- status icon rendering
- player name rendering
- equipment icon rendering
- tooltips

Reasoning:

Separating row rendering from main window creation will make UI changes less
risky.

### Util/Units.lua

Own unit-token and GUID lookup helpers.

Current functions that belong here:

- `GetUnitIdOfPlayerGuid`
- `IsPlayerInGroup`
- `IsLocalPlayerGuid`, if not kept in `ScanSession`

Rules:

- validate cached roster unit IDs with `UnitGUID(unitId) == playerGuid`
- prefer current target when appropriate for target scans
- fall back to raid/party scans only when cached metadata is absent or stale

### Util/Inventory.lua

Own low-level inventory API wrappers.

Current functions that belong here:

- `GetInventorySlotNames`, if not moved to `Config/Slots.lua`
- `InventorySlotTooltipHasItem`
- `GetInventorySlotState`
- `IsInventorySlotEvidenceState`
- `GetInventorySnapshotEvidenceCount`
- `CanConfirmEmptyInventorySlot`

This can either be a util module or part of `Inspection/SlotResolver.lua`. The
key is to keep raw WoW inventory probing separate from rule checks.

### Util/Tables.lua

Only keep this if there are enough generic table helpers to justify it.

Current candidate:

- `tContains`

If only one helper remains, prefer inlining it or keeping it local to the module
that needs it.

## Data Model Improvements

### Current Problem

`PlayerGearInfo[playerGuid]` currently stores both player result data and runtime
scan state.

Examples of result-like data:

- `PlayerName`
- `PlayerGuid`
- `EquippedItems`
- `ProblematicItems`
- `PendingItemMetadata`
- `LastScanTime`

Examples of runtime-like data:

- `CheckRequested`
- `CheckStatus`
- `pendingChecks`
- `retryAttempts`
- `ForceScanRequested`
- `ScanGeneration`
- `QueuedScanReason`
- `IsRosterTracked`
- `CurrentUnitId`
- `RosterSortIndex`
- `RosterGroupType`

This mixing makes it harder to reason about clear/reset behavior. For example,
clearing scans, clearing all tracked players, target rescans, roster
reconciliation, and delayed retries all write to the same object.

### Recommended Direction

Move toward three conceptual records:

```lua
PlayerRecord = {
    guid = "...",
    name = "Name",
    roster = {
        tracked = true,
        unitId = "raid8",
        sortIndex = 8,
        groupType = "raid",
    },
    scan = {
        status = "Successful",
        generation = 42,
        lastScanTime = 123456,
        requested = false,
        forced = false,
        queuedReason = nil,
        retryAttempts = 0,
        pendingChecks = 0,
    },
    result = {
        equippedItems = {},
        problems = {},
        pendingMetadata = {},
    },
}
```

This does not need to be done immediately. It can be introduced gradually with
helper functions that hide the old field names first.

### Problem Data Shape

Current problem shape:

```lua
ProblematicItems[itemLink] = { "Missing Gem", "Low Item Level" }
```

This is good enough for reporting, but weak for UI details and duplicate item
links.

Better future shape:

```lua
Problems = {
    {
        slotName = "ChestSlot",
        itemLink = "...",
        ruleId = "missing_gems",
        message = "Missing Gem",
    },
}
```

Benefits:

- shows exactly which slot has the issue
- supports duplicate item links in two slots
- gives UI a stable rule ID
- gives reporting and UI the same normalized data
- makes filtering/grouping easier

Migration path:

1. Add a helper that records problems in both old and new shapes.
2. Update reporting to consume the new shape when present.
3. Update UI to consume the new shape.
4. Remove old `ProblematicItems` only when no caller needs it.

Since there is no backwards compatibility requirement unless explicitly stated,
this can also be done as a direct shape change if we are ready to update all
callers in one pass.

## Behavioral Invariants To Preserve

These are the important rules that should be checked after every refactor phase.

- A scan queue can only start one active scan at a time.
- A scan generation is created before `NotifyInspect`.
- Every timer callback validates scan generation before writing state.
- Every slot retry callback validates scan generation before writing state.
- Every inspect-ready callback validates the current player and generation.
- Every terminal scan path goes through one finish function.
- Once a player is `Successful`, no queued copy or player-owned retry timer
  should remain for that player.
- `Partial` scans may schedule a delayed follow-up, but that follow-up must not
  alter a later successful scan.
- Target scans can force a fresh scan and clear old item info.
- Group scans should only retry while the player is still in the group.
- Target scans should only retry while the current target still matches the
  requested player.
- Leaving a group clears tracked players, queue, current scan, and timers.
- Joining a group from groupless clears stale previous list state first.
- Roster updates remove players who left and preserve raid/party ordering.
- The local player should be included in group scans where intended.
- UI hidden/open state should not affect scan correctness.
- Debug reporting should still print full item links.

## Incremental Refactor Phases

### Phase 0: Establish Refactor Safety Checks

Before moving code, keep the standard verification commands visible and use them
after every phase.

Commands:

```sh
luac5.1 -p Core.lua Debug.lua Helper.lua Inspection.lua Reporting.lua UI.lua
git diff --check
luacheck . --exclude-files Libs
```

After files are split, update the `luac5.1 -p` command to include the new files.

Expected current lint state:

- many warnings for WoW globals and style
- no syntax errors
- no luacheck errors

Manual smoke checks after behavior-affecting phases:

- group scan completes players one at a time
- green checkmark does not revert to scanning after completion
- target scan clears old target item info and performs a fresh scan
- debug report prints full item links
- partial scans retry later without affecting successful scans
- leaving combat resumes queued scans
- clearing scans cancels current scan, queue, and timers
- leaving group clears list and active work
- joining group from groupless starts from a cleared list
- roster order follows current `raidN`/`partyN`

### Phase 1: Extract Constants And Slots

Risk: low.

Create:

- `Config/Constants.lua`
- `Config/Slots.lua`

Move:

- inventory slot sentinel strings
- item metadata pending sentinel
- retry counts and delays
- empty-slot confirmation thresholds
- item level threshold
- slot order
- inventory snapshot evidence slot order
- status texture mapping if desired

Update callers:

- `Core.lua`
- `Inspection.lua`
- `Helper.lua`
- `UI.lua`

Keep existing public names on `GearPolice` initially if that minimizes churn.
Example:

```lua
GearPolice.Constants = GearPolice.Constants or {}
GearPolice.InventorySlotPending = GearPolice.Constants.InventorySlotPending
```

Completion criteria:

- no behavior changes
- `.toc` loads new files before modules that use them
- static checks pass

### Phase 2: Extract Rule Configuration

Risk: low to medium.

Create:

- `Config/Rules.lua`

Move out of `Inspection:CheckUnit`:

- `checks`
- `slotConfig`

Use stable rule IDs:

- `missing_gems`
- `missing_enchant`
- `missing_waist_extra_gem`
- `missing_upgrade`
- `low_item_level`

Recommended rule structure:

```lua
GearPolice.RuleDefinitions = {
    missing_gems = {
        message = "Missing Gem",
        evaluate = function(itemLink, context)
            return GearPolice.Inspection:IsItemMissingGems(itemLink, context)
        end,
    },
}

GearPolice.SlotRuleIds = {
    HeadSlot = { "missing_gems", "low_item_level", "missing_upgrade" },
}
```

Completion criteria:

- check output remains unchanged
- report messages remain unchanged
- item links in debug report remain unchanged

### Phase 3: Extract Timer Service

Risk: medium.

Create:

- `Services/Timers.lua`

Move:

- `ScheduleManagedTimer`
- `CancelManagedTimersForPlayer`
- `CancelAllManagedTimers`

Keep the method names available as `GearPolice:ScheduleManagedTimer(...)` at
first to avoid touching all callers in one pass.

Important:

- preserve player-owned timer cancellation
- preserve global timer cancellation
- preserve `scanQueueTimer` cleanup, even if queue-specific handling remains in
  `Core.lua` for this phase

Completion criteria:

- clearing scans cancels timers
- removing a player cancels that player's timers
- delayed partial retry still works

### Phase 4: Extract PlayerStore

Risk: medium.

Create:

- `State/PlayerStore.lua`

Move:

- `SetPlayerGuidToDefaultInPlayerGearInfo`
- `ResetPlayerGearInfo`
- player record normalization
- parts of `ClearAllTrackedPlayers`
- helper accessors for `PlayerGearInfo`

Recommended API:

```lua
GearPolice.PlayerStore:Ensure(playerGuid)
GearPolice.PlayerStore:Get(playerGuid)
GearPolice.PlayerStore:ResetForScan(playerGuid, playerName)
GearPolice.PlayerStore:Remove(playerGuid)
GearPolice.PlayerStore:ClearAll()
GearPolice.PlayerStore:IsScanComplete(playerInfo)
```

Keep compatibility wrappers on `GearPolice` temporarily if needed.

Completion criteria:

- target scan still clears old target item info
- group scan still creates missing records
- clear button still clears all records

### Phase 5: Extract Roster Service

Risk: medium.

Create:

- `Services/Roster.lua`

Move:

- roster snapshot creation
- roster reset/refresh
- roster metadata application
- roster reconciliation
- group member processing
- ordered roster GUID list, unless moved to UI view model

Recommended API:

```lua
GearPolice.Roster:BuildSnapshot()
GearPolice.Roster:RefreshSnapshot()
GearPolice.Roster:Reconcile(snapshot)
GearPolice.Roster:GetOrderedGuids()
GearPolice.Roster:IsPlayerPresent(playerGuid)
GearPolice.Roster:GetUnitId(playerGuid)
```

Completion criteria:

- party and raid ordering still work
- local player inclusion still works
- players leaving group are removed
- target-only rows remain while grouped
- leaving group clears everything
- joining group from groupless clears stale list first

### Phase 6: Extract ScanQueue

Risk: medium to high.

Create:

- `Services/ScanQueue.lua`

Move:

- queue add/remove
- queue de-duplication
- queued reason storage
- queue dispatch throttle
- queue dispatch entry point
- combat pause/resume logic

Recommended API:

```lua
GearPolice.ScanQueue:Add(playerGuid, options)
GearPolice.ScanQueue:Remove(playerGuid)
GearPolice.ScanQueue:Contains(playerGuid)
GearPolice.ScanQueue:ScheduleProcess(delay)
GearPolice.ScanQueue:Process()
GearPolice.ScanQueue:Clear()
```

Do not let this module own scan completion. It should call `ScanSession:Start`
and then stop.

Completion criteria:

- exactly one active scan at a time
- queue continues after scan finish
- successful player is not requeued without force
- target scan can be placed at the front
- combat pauses queue dispatch and resumes later

### Phase 7: Extract ScanSession

Risk: high.

Create:

- `Services/ScanSession.lua`

Move:

- current scan state
- current scan identity checks
- scan availability checks
- starting `NotifyInspect`
- local-player scan path
- inspect-ready timeout
- inspect-ready handler
- retry inspection
- finish scan
- delayed follow-up scan scheduling
- clear current scan

Recommended API:

```lua
GearPolice.ScanSession:Start(playerGuid, reason, generation)
GearPolice.ScanSession:StartInspectionOfUnit(unitId, reason, generation)
GearPolice.ScanSession:OnInspectReady(playerGuid)
GearPolice.ScanSession:Retry(playerGuid, attempt, generation)
GearPolice.ScanSession:Finish(playerGuid, generation, status, options)
GearPolice.ScanSession:ClearForPlayer(playerGuid)
GearPolice.ScanSession:IsCurrent(playerGuid, generation)
```

This is the most sensitive phase. Avoid combining it with unrelated cleanup.

Completion criteria:

- stale inspect-ready events do nothing
- stale retry timers do nothing
- partial follow-up does not affect later successful scans
- successful scans leave no queued copies and no player-owned timers
- target scan behavior remains forced/fresh

### Phase 8: Split Inspection.lua

Risk: medium.

Create:

- `Inspection/ItemChecks.lua`
- `Inspection/SlotResolver.lua`
- `Inspection/CheckRunner.lua`

Move:

- item-link parsing and metadata checks to `ItemChecks`
- slot probing/retry/empty confirmation to `SlotResolver`
- slot scheduling and rule application to `CheckRunner`

Recommended API:

```lua
GearPolice.ItemChecks:IsMissingGems(itemLink)
GearPolice.SlotResolver:Resolve(playerInfo, slotName, options, callback)
GearPolice.CheckRunner:CheckUnit(playerInfo, onComplete, generation)
```

Completion criteria:

- normal dual-wield/shield target resolves offhand
- two-handed/ranged target marks offhand empty
- missing gem/enchant reports match previous behavior
- slow inspect data still produces `Partial`
- debug report still prints item links

### Phase 9: Split UI.lua

Risk: medium.

Create:

- `UI/Widgets/ItemIcon.lua`
- `UI/ViewModel.lua`
- `UI/MainWindow.lua`
- `UI/PlayerRows.lua`

Move:

- custom AceGUI widget to `UI/Widgets/ItemIcon.lua`
- frame/buttons/dropdown/scroll setup to `MainWindow`
- row cache and row updates to `PlayerRows`
- player state to render-state mapping to `ViewModel`

Recommended API:

```lua
GearPolice.UI:Show()
GearPolice.UI:Update()
GearPolice.UI.ViewModel:BuildRows()
GearPolice.UI.PlayerRows:Render(scrollContainer, rows)
```

Completion criteria:

- UI can be opened/closed repeatedly
- row order changes when roster order changes
- item icons/tooltips still show real item links
- problematic item border does not leak to other icons
- clear/refresh/target/report mode controls still work

### Phase 10: Normalize Problem Records

Risk: medium.

This phase enables the low-priority UI feature cleanly.

Change from item-link keyed problem strings toward structured records:

```lua
{
    slotName = "ChestSlot",
    itemLink = "...",
    ruleId = "missing_gems",
    message = "Missing Gem",
}
```

Update:

- check runner
- reporting
- UI view model
- debug output

Completion criteria:

- reports match current message content
- UI can identify which item is problematic and why
- duplicate item links in two slots are represented correctly

## Suggested First Implementation Sequence

The safest initial sequence is:

1. `Config/Constants.lua`
2. `Config/Slots.lua`
3. `Config/Rules.lua`
4. `Services/Timers.lua`
5. `State/PlayerStore.lua`

These reduce `Core.lua` and `Inspection.lua` without touching the most fragile
inspect-ready lifecycle first.

The highest-risk sequence is:

1. `Services/ScanQueue.lua`
2. `Services/ScanSession.lua`

Do these only after the lower-risk extractions are complete and the behavior is
easy to verify.

## Coding Guidelines For The Refactor

- Prefer moving one responsibility per commit.
- Keep old method names as wrappers during extraction if that avoids a broad diff.
- Delete wrappers only after callers are moved.
- Do not mix behavior changes with file movement unless the behavior change is
  required for the extraction.
- Keep public module APIs small.
- Avoid making modules read/write raw `GearPolice.db.global.PlayerGearInfo`
  directly unless they are the player store or a temporary compatibility layer.
- Keep all timer callbacks generation-guarded.
- Keep UI rendering driven by data, not by scan policy.
- Do not add abstractions just to reduce line count; add them where ownership is
  currently unclear.

## Commit Strategy

Recommended commit shape:

- one commit for constants/slot extraction
- one commit for rule config extraction
- one commit for timer service extraction
- one commit for player store extraction
- one commit for roster service extraction
- one commit for scan queue extraction
- one commit for scan session extraction
- one commit per inspection split
- one commit per UI split
- one commit for structured problem records

Each commit should include:

- `.toc` load order update if files were added
- static verification output summary
- no unrelated formatting churn

## Done State

The refactor is complete when:

- `Core.lua` is mostly bootstrap/event routing
- scan queue and scan session have clear separate owners
- roster logic is isolated
- player record shape has one owner
- inspection rules are configured outside the scan runner
- UI renders view models instead of raw scan internals
- problem records are structured enough for both reporting and detailed UI
- all known scan lifecycle invariants still hold
