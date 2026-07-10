local GearPolice = GearPolice

GearPolice.ScanSession = GearPolice.ScanSession or {}

local ScanSession = GearPolice.ScanSession

function ScanSession.ClearCurrent(addon, playerGuid)
    if not playerGuid or not addon.currentScan or addon.currentScan.playerGuid ~= playerGuid then
        return
    end

    addon.currentScan = nil

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end
end

function ScanSession.IsCurrent(addon, playerGuid, scanGeneration)
    local currentScan = addon.currentScan
    if not currentScan or currentScan.playerGuid ~= playerGuid then
        return false
    end

    if scanGeneration and currentScan.generation ~= scanGeneration then
        return false
    end

    return true
end

function ScanSession.IsTargetAvailable(addon, playerGuid, reason)
    if not playerGuid then
        return false
    end

    reason = addon:NormalizeScanReason(reason)
    if reason == "target" then
        return UnitGUID("target") == playerGuid
    end

    return addon.Helper:IsPlayerInGroup(playerGuid)
end

function ScanSession.GetUnitId(addon, playerGuid, reason)
    reason = addon:NormalizeScanReason(reason)
    if not addon:IsScanTargetAvailable(playerGuid, reason) then
        return nil
    end

    if reason == "target" then
        return "target"
    end

    return addon.Helper:GetUnitIdOfPlayerGuid(playerGuid)
end

function ScanSession.IsLocalPlayer(_addon, playerGuid)
    return playerGuid and UnitGUID("player") == playerGuid
end

local function IsCurrentRosterPlayer(addon, playerGuid)
    local roster = addon.currentRoster
    if not roster or not roster.presentGuids or not roster.presentGuids[playerGuid] then
        return false
    end

    local unitId = roster.unitIdByGuid and roster.unitIdByGuid[playerGuid]
    return unitId and UnitGUID(unitId) == playerGuid
end

local function ReconcileObsoleteTargetWork(addon, playerGuids)
    local changed = false

    for playerGuid in pairs(playerGuids) do
        local playerInfo = addon.PlayerStore:Get(playerGuid)
        local isRosterPlayer = IsCurrentRosterPlayer(addon, playerGuid)

        addon:ClearScheduledWorkForPlayer(playerGuid)

        if isRosterPlayer then
            playerInfo = playerInfo or addon.PlayerStore:Ensure(playerGuid)
            if playerInfo then
                addon:ApplyCurrentRosterMetadata(playerGuid, playerInfo)
                playerInfo.retryAttempts = 0
                addon:AddToScanQueue(playerGuid, true, "group", true)
            end
        else
            addon:RemovePlayerFromTracking(playerGuid)
        end

        changed = true
    end

    if changed then
        addon.UI:UpdateUI()
        addon:ProcessScanQueue()
    end

    return changed
end

function ScanSession.HandleTargetChanged(addon)
    addon:RefreshCurrentRosterSnapshot()

    local currentTargetGuid = UnitGUID("target")
    local obsoletePlayerGuids = {}
    local currentScan = addon.currentScan

    if currentScan and currentScan.reason == "target"
        and currentScan.playerGuid ~= currentTargetGuid then
        obsoletePlayerGuids[currentScan.playerGuid] = true
    end

    for playerGuid, reason in pairs(addon.queuedScanReasons or {}) do
        if reason == "target" and playerGuid ~= currentTargetGuid then
            obsoletePlayerGuids[playerGuid] = true
        end
    end

    for playerGuid, retry in pairs(addon.delayedScanRetries or {}) do
        if retry.reason == "target" and playerGuid ~= currentTargetGuid then
            obsoletePlayerGuids[playerGuid] = true
        end
    end

    return ReconcileObsoleteTargetWork(addon, obsoletePlayerGuids)
end

function ScanSession.Finish(addon, playerGuid, scanGeneration, status, options)
    if not addon:IsCurrentScan(playerGuid, scanGeneration) then
        return false
    end

    options = options or {}

    local currentScan = addon.currentScan
    local playerInfo = addon.db.global.PlayerGearInfo[playerGuid]
    if playerInfo and scanGeneration and playerInfo.ScanGeneration ~= scanGeneration then
        return false
    end

    addon:CancelManagedTimersForPlayer(playerGuid)
    if addon.delayedScanRetries then
        addon.delayedScanRetries[playerGuid] = nil
    end
    addon:RemoveFromScanQueue(playerGuid)

    addon.currentScan = nil

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end

    if playerInfo then
        playerInfo.CheckRequested = false
        playerInfo.CheckStatus = status
        playerInfo.pendingChecks = 0
        playerInfo.retryAttempts = 0
        playerInfo.ForceScanRequested = false
        if options.updateLastScanTime then
            playerInfo.LastScanTime = time()
        end
    end

    if options.debugMessage then
        addon.Debug:Message(options.debugMessage)
    end

    addon.UI:UpdateUI()
    addon:ScheduleScanQueueProcessing(addon.scanInterval)

    return true, playerInfo, currentScan
end

function ScanSession.ScheduleDelayedRetry(addon, playerGuid, scanGeneration, reason, expectedStatus, delay)
    reason = addon:NormalizeScanReason(reason)

    addon.delayedScanRetries = addon.delayedScanRetries or {}
    local retryRecord = {
        generation = scanGeneration,
        reason = reason,
        expectedStatus = expectedStatus,
    }
    addon.delayedScanRetries[playerGuid] = retryRecord

    local timerHandle
    timerHandle = addon:ScheduleManagedTimer(function()
        if addon.delayedScanRetries[playerGuid] ~= retryRecord then
            return
        end

        if reason == "target" and not addon:IsScanTargetAvailable(playerGuid, reason) then
            addon:OnPlayerTargetChanged()
            return
        end

        addon.delayedScanRetries[playerGuid] = nil
        local playerInfo = addon.db.global.PlayerGearInfo[playerGuid]
        if not playerInfo then
            return
        end

        if playerInfo.ScanGeneration ~= scanGeneration or playerInfo.CheckStatus ~= expectedStatus then
            return
        end

        if not addon:IsScanTargetAvailable(playerGuid, reason) then
            return
        end

        playerInfo.retryAttempts = 0
        addon:AddToScanQueue(playerGuid, true, reason)
        addon.UI:UpdateUI()
        addon:ProcessScanQueue()
    end, delay, playerGuid)

    retryRecord.timerHandle = timerHandle
    if not timerHandle and addon.delayedScanRetries[playerGuid] == retryRecord then
        addon.delayedScanRetries[playerGuid] = nil
    end

    return timerHandle
end

function ScanSession.ScheduleInspectReadyTimeout(addon, playerGuid, scanGeneration)
    addon:ScheduleManagedTimer(function()
        if not addon:IsCurrentScan(playerGuid, scanGeneration) then
            return
        end

        if addon.currentScan.inspectReadyReceived then
            return
        end

        addon.Debug:Message("INSPECT_READY timed out; retrying scan.")
        addon:RetryInspection(playerGuid, 1, scanGeneration)
    end, addon.inspectReadyTimeout, playerGuid)
end

function ScanSession.RunChecks(addon, playerGuid, scanGeneration)
    local playerInfo = addon.db.global.PlayerGearInfo[playerGuid]
    if not addon:IsCurrentScan(playerGuid, scanGeneration) then
        return
    end

    if not playerInfo or not playerInfo.CheckRequested then
        addon:FinishScan(playerGuid, scanGeneration, "Failed")
        return
    end

    if playerInfo.ScanGeneration ~= scanGeneration then
        return
    end

    if addon.currentScan.inspectReadyReceived then
        return
    end

    addon.currentScan.inspectReadyReceived = true
    playerInfo.CheckStatus = "InProgress"
    playerInfo.EquippedItems = {}
    addon.UI:UpdateUI()

    addon.Inspection:CheckUnit(playerInfo, function(updatedPlayerInfo)
        if not addon:IsCurrentScan(playerGuid, scanGeneration)
            or updatedPlayerInfo.ScanGeneration ~= scanGeneration then
            return
        end

        local status
        if addon:HasPendingEquippedItems(updatedPlayerInfo)
            or addon:HasPendingItemMetadata(updatedPlayerInfo) then
            status = "Partial"
        else
            status = "Successful"
        end

        local finished, finishedPlayerInfo, completedScan =
            addon:FinishScan(playerGuid, scanGeneration, status, {
                updateLastScanTime = true,
                debugMessage = "Scan completed for: " .. (updatedPlayerInfo.PlayerName or "Unknown"),
            })

        if finished then
            addon:MaybeSendReportOffer(finishedPlayerInfo, completedScan, status)
        end

        if finished and status == "Partial" and finishedPlayerInfo and completedScan then
            addon:ScheduleDelayedScanRetry(
                playerGuid,
                scanGeneration,
                completedScan.reason,
                "Partial",
                60
            )
        end
    end, scanGeneration)
end

function ScanSession.StartInspection(addon, unitId, reason, scanGeneration)
    if not addon.currentScan then
        return
    end

    reason = addon:NormalizeScanReason(reason or addon.currentScan.reason)
    local playerGuid = addon.currentScan.playerGuid

    if not addon:IsCurrentScan(playerGuid, scanGeneration) then
        return
    end

    if not unitId or not UnitExists(unitId) or UnitGUID(unitId) ~= playerGuid then
        addon:RetryInspection(playerGuid, 1, scanGeneration)
        return
    end

    local playerInfo = addon.db.global.PlayerGearInfo[playerGuid]
    if not playerInfo or not playerInfo.CheckRequested then
        addon:FinishScan(playerGuid, scanGeneration, "Failed")
        return
    end

    if addon:IsPlayerScanComplete(playerInfo) and not playerInfo.ForceScanRequested then
        addon:FinishScan(playerGuid, scanGeneration, "Successful")
        return
    end

    if InCombatLockdown() then
        addon.Debug:Message("Cannot inspect in combat; queued scan for later.")
        addon:ClearCurrentScanForPlayer(playerGuid)
        addon:AddToScanQueue(playerGuid, true, reason, true)
        return
    end

    if playerInfo.CheckStatus == "Failed" then
        addon:FinishScan(playerGuid, scanGeneration, "Failed")
        return
    end

    playerInfo.CheckStatus = "InProgress"
    addon.currentScan.unitId = unitId
    addon.currentScan.reason = reason
    addon.currentScan.inspectReadyReceived = false

    if addon:IsLocalPlayerGuid(playerGuid) then
        addon:RunInspectionChecks(playerGuid, scanGeneration)
        return
    end

    if CanInspect(unitId) then
        NotifyInspect(unitId)
        addon:ScheduleInspectReadyTimeout(playerGuid, scanGeneration)
    else
        addon:RetryInspection(playerGuid, 1, scanGeneration)
    end
end

function ScanSession.RetryInspection(addon, playerGuid, attempt, scanGeneration)
    local maxAttempts = 5
    attempt = attempt or 1

    if not addon:IsCurrentScan(playerGuid, scanGeneration) then
        return
    end

    if addon.currentScan.inspectReadyReceived then
        return
    end

    local reason = addon:NormalizeScanReason(addon.currentScan.reason)
    local playerInfo = addon.db.global.PlayerGearInfo[playerGuid]

    if not playerInfo or not playerInfo.CheckRequested then
        addon:FinishScan(playerGuid, scanGeneration, "Failed")
        return
    end

    if scanGeneration and playerInfo.ScanGeneration ~= scanGeneration then
        return
    end

    if not addon:IsScanTargetAvailable(playerGuid, reason) then
        if reason == "target" then
            addon:OnPlayerTargetChanged()
            return
        end

        addon:FinishScan(playerGuid, scanGeneration, "Failed")
        return
    end

    playerInfo.retryAttempts = playerInfo.retryAttempts or 0

    if playerInfo.retryAttempts >= maxAttempts then
        local finished, finishedPlayerInfo, completedScan =
            addon:FinishScan(playerGuid, scanGeneration, "TemporaryFailed")
        if finished and finishedPlayerInfo and completedScan then
            addon:ScheduleDelayedScanRetry(
                playerGuid,
                finishedPlayerInfo.ScanGeneration,
                completedScan.reason,
                "TemporaryFailed",
                300
            )
        end
        return
    end

    playerInfo.retryAttempts = playerInfo.retryAttempts + 1
    addon:ScheduleManagedTimer(function()
        if not addon:IsCurrentScan(playerGuid, scanGeneration) then
            return
        end

        if addon.currentScan.inspectReadyReceived then
            return
        end

        local currentPlayerInfo = addon.db.global.PlayerGearInfo[playerGuid]
        if not currentPlayerInfo or not currentPlayerInfo.CheckRequested then
            addon:FinishScan(playerGuid, scanGeneration, "Failed")
            return
        end

        if scanGeneration and currentPlayerInfo.ScanGeneration ~= scanGeneration then
            return
        end

        local unitId = addon:GetScanUnitId(playerGuid, addon.currentScan.reason)
        if unitId then
            addon:StartInspectionOfUnit(unitId, addon.currentScan.reason, scanGeneration)
        else
            addon:RetryInspection(playerGuid, attempt + 1, scanGeneration)
        end
    end, addon.scanInterval * attempt, playerGuid)
end

function ScanSession.OnInspectReady(addon, _eventName, playerGuid)
    if not playerGuid then return end

    if not addon:IsCurrentScan(playerGuid) then
        return
    end

    local scanGeneration = addon.currentScan.generation
    addon:RunInspectionChecks(playerGuid, scanGeneration)
end

function GearPolice:ClearCurrentScanForPlayer(playerGuid)
    return ScanSession.ClearCurrent(self, playerGuid)
end

function GearPolice:IsCurrentScan(playerGuid, scanGeneration)
    return ScanSession.IsCurrent(self, playerGuid, scanGeneration)
end

function GearPolice:IsScanTargetAvailable(playerGuid, reason)
    return ScanSession.IsTargetAvailable(self, playerGuid, reason)
end

function GearPolice:GetScanUnitId(playerGuid, reason)
    return ScanSession.GetUnitId(self, playerGuid, reason)
end

function GearPolice:IsLocalPlayerGuid(playerGuid)
    return ScanSession.IsLocalPlayer(self, playerGuid)
end

function GearPolice:FinishScan(playerGuid, scanGeneration, status, options)
    return ScanSession.Finish(self, playerGuid, scanGeneration, status, options)
end

function GearPolice:ScheduleDelayedScanRetry(playerGuid, scanGeneration, reason, expectedStatus, delay)
    return ScanSession.ScheduleDelayedRetry(self, playerGuid, scanGeneration, reason, expectedStatus, delay)
end

function GearPolice:ScheduleInspectReadyTimeout(playerGuid, scanGeneration)
    return ScanSession.ScheduleInspectReadyTimeout(self, playerGuid, scanGeneration)
end

function GearPolice:RunInspectionChecks(playerGuid, scanGeneration)
    return ScanSession.RunChecks(self, playerGuid, scanGeneration)
end

function GearPolice:StartInspectionOfUnit(unitId, reason, scanGeneration)
    return ScanSession.StartInspection(self, unitId, reason, scanGeneration)
end

function GearPolice:RetryInspection(playerGuid, attempt, scanGeneration)
    return ScanSession.RetryInspection(self, playerGuid, attempt, scanGeneration)
end

function GearPolice:OnInspectReady(eventName, playerGuid)
    return ScanSession.OnInspectReady(self, eventName, playerGuid)
end

function GearPolice:OnPlayerTargetChanged()
    return ScanSession.HandleTargetChanged(self)
end
