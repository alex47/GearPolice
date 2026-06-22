local GearPolice = GearPolice

GearPolice.RuntimeState = GearPolice.RuntimeState or {}

local RuntimeState = GearPolice.RuntimeState

function RuntimeState.Initialize(addon)
    addon.scanQueue = {}
    addon.queuedScanReasons = {}
    addon.currentScan = nil
    addon.scanQueueTimer = nil
    addon.isScanning = false
    addon.activeScanGuids = {}
    addon.activeTimers = {}
    addon.activePlayerTimers = {}
    addon.currentRoster = nil
    addon.wasGrouped = IsInRaid() or IsInGroup()
    addon:ResetRosterSnapshot()
end

function RuntimeState.ClearScheduledWorkForPlayer(addon, playerGuid)
    if not playerGuid then
        return
    end

    addon:CancelManagedTimersForPlayer(playerGuid)
    addon:RemoveFromScanQueue(playerGuid)
    addon:ClearCurrentScanForPlayer(playerGuid)
    if addon.ClearPendingReportOffer then
        addon:ClearPendingReportOffer(playerGuid)
    end
end

function RuntimeState.StopAllScans(addon)
    addon:CancelAllManagedTimers()
    if addon.ClearPendingReportOffers then
        addon:ClearPendingReportOffers()
    end

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end

    addon.scanQueue = {}
    addon.queuedScanReasons = {}
    addon.currentScan = nil
    addon.activeScanGuids = {}
    addon.isScanning = false
    addon.scanQueueTimer = nil
    addon:ResetRosterSnapshot()

    addon.PlayerStore:MarkAllScansCancelled()
end

function RuntimeState.RemovePlayerFromTracking(addon, playerGuid)
    if not playerGuid or not addon.db or not addon.db.global then
        return
    end

    addon:ClearScheduledWorkForPlayer(playerGuid)
    addon.PlayerStore:Remove(playerGuid)
    addon:RemoveGuidFromCurrentRoster(playerGuid)
end

function RuntimeState.ClearAllTrackedPlayers(addon)
    addon:StopAllScans()
    addon.PlayerStore:ClearAll()
    addon:ResetRosterSnapshot()
    addon.UI:UpdateUI()
end

function RuntimeState.ClearTrackedPlayersForRosterTransition(addon)
    addon:StopAllScans()
    addon.PlayerStore:ClearAll()
    addon:ResetRosterSnapshot()
end

function GearPolice:InitializeRuntimeState()
    return RuntimeState.Initialize(self)
end

function GearPolice:ClearScheduledWorkForPlayer(playerGuid)
    return RuntimeState.ClearScheduledWorkForPlayer(self, playerGuid)
end

function GearPolice:StopAllScans()
    return RuntimeState.StopAllScans(self)
end

function GearPolice:RemovePlayerFromTracking(playerGuid)
    return RuntimeState.RemovePlayerFromTracking(self, playerGuid)
end

function GearPolice:ClearAllTrackedPlayers()
    return RuntimeState.ClearAllTrackedPlayers(self)
end

function GearPolice:ClearTrackedPlayersForRosterTransition()
    return RuntimeState.ClearTrackedPlayersForRosterTransition(self)
end
