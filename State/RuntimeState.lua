local GearPolice = GearPolice

GearPolice.RuntimeState = GearPolice.RuntimeState or {}

local RuntimeState = GearPolice.RuntimeState

local function ClearTrackedPlayers(addon, updateUI)
    addon:StopAllScans()
    addon.PlayerStore:ClearAll()

    if updateUI then
        addon.UI:UpdateUI()
    end
end

function RuntimeState.Initialize(addon)
    addon.scanQueue = {}
    addon.queuedScanReasons = {}
    addon.currentScan = nil
    addon.scanQueueTimer = nil
    addon.delayedScanRetries = {}
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
    if addon.delayedScanRetries then
        addon.delayedScanRetries[playerGuid] = nil
    end
    addon:RemoveFromScanQueue(playerGuid)
    addon:ClearCurrentScanForPlayer(playerGuid)
    if addon.ClearPendingReportOffer then
        addon:ClearPendingReportOffer(playerGuid)
    end
    if addon.ClearPendingPublicScanAnnouncement then
        addon:ClearPendingPublicScanAnnouncement(playerGuid)
    end
end

function RuntimeState.StopAllScans(addon)
    addon:CancelAllManagedTimers()
    if addon.ClearPendingReportOffers then
        addon:ClearPendingReportOffers()
    end
    if addon.ClearPendingPublicScanAnnouncements then
        addon:ClearPendingPublicScanAnnouncements()
    end

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end

    addon.scanQueue = {}
    addon.queuedScanReasons = {}
    addon.currentScan = nil
    addon.delayedScanRetries = {}
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
    ClearTrackedPlayers(addon, true)
end

function RuntimeState.ClearTrackedPlayersForRosterTransition(addon)
    ClearTrackedPlayers(addon, false)
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
