local GearPolice = GearPolice

GearPolice.ScanSession = GearPolice.ScanSession or {}

local ScanSession = GearPolice.ScanSession
local Constants = GearPolice.Constants
local ScanReason = GearPolice.Constants.ScanReason
local ScanStatus = GearPolice.Constants.ScanStatus

local function ClearCurrentScanWork(addon, playerGuid)
    addon:CancelManagedTimersForPlayer(playerGuid)
    addon:ClearCurrentScanForPlayer(playerGuid)
end

local function RequeueCurrentScan(addon, playerGuid, scanGeneration, reason, addToFront)
    if not addon:IsCurrentScan(playerGuid, scanGeneration) then
        return false
    end

    local playerInfo = addon.db.global.PlayerGearInfo[playerGuid]
    if not playerInfo or playerInfo.ScanGeneration ~= scanGeneration then
        return false
    end

    ClearCurrentScanWork(addon, playerGuid)

    playerInfo.retryAttempts = 0
    addon:AddToScanQueue(playerGuid, true, reason, addToFront)
    addon.UI:UpdateUI()
    return true
end

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
    if reason == ScanReason.Target then
        return UnitGUID("target") == playerGuid
    end

    return addon.Units.IsPlayerInGroup(playerGuid)
end

function ScanSession.GetUnitId(addon, playerGuid, reason)
    reason = addon:NormalizeScanReason(reason)
    if not addon:IsScanTargetAvailable(playerGuid, reason) then
        return nil
    end

    if reason == ScanReason.Target then
        return "target"
    end

    return addon.Units.GetUnitIdOfPlayerGuid(playerGuid)
end

function ScanSession.IsLocalPlayer(_addon, playerGuid)
    return playerGuid and UnitGUID("player") == playerGuid
end

function ScanSession.DeferUntilInspectable(addon, playerGuid, scanGeneration)
    if not addon:IsCurrentScan(playerGuid, scanGeneration) then
        return false
    end

    local reason = addon:NormalizeScanReason(addon.currentScan.reason)
    if not addon:IsScanTargetAvailable(playerGuid, reason) then
        if reason == ScanReason.Target then
            addon:OnPlayerTargetChanged()
        else
            addon:FinishScan(playerGuid, scanGeneration, ScanStatus.Failed)
        end
        return false
    end

    local requeued = RequeueCurrentScan(
        addon,
        playerGuid,
        scanGeneration,
        reason,
        reason == ScanReason.Target
    )
    if not requeued and addon:IsCurrentScan(playerGuid, scanGeneration) then
        ClearCurrentScanWork(addon, playerGuid)
        addon.UI:UpdateUI()
    end

    if requeued and not InCombatLockdown() then
        addon:ProcessScanQueue()
    elseif not addon.currentScan and not InCombatLockdown() then
        addon:ProcessScanQueue()
    end

    return requeued
end

function ScanSession.PauseForCombat(addon, playerGuid, scanGeneration)
    local currentScan = addon.currentScan
    if not currentScan then
        return false
    end

    playerGuid = playerGuid or currentScan.playerGuid
    scanGeneration = scanGeneration or currentScan.generation
    local reason = addon:NormalizeScanReason(currentScan.reason)
    local requeued = RequeueCurrentScan(addon, playerGuid, scanGeneration, reason, true)
    if not requeued and addon:IsCurrentScan(playerGuid, scanGeneration) then
        ClearCurrentScanWork(addon, playerGuid)
        addon.UI:UpdateUI()
    end

    if requeued then
        addon.Debug:Message("Active scan paused while in combat.")
    end
    return requeued
end

function ScanSession.OnCombatStarted(addon)
    return ScanSession.PauseForCombat(addon)
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

        if isRosterPlayer then
            addon:ClearScheduledWorkForPlayer(playerGuid)
            playerInfo = playerInfo or addon.PlayerStore:Ensure(playerGuid)
            if playerInfo then
                addon:ApplyCurrentRosterMetadata(playerGuid, playerInfo)
                playerInfo.retryAttempts = 0
                addon:AddToScanQueue(playerGuid, true, ScanReason.Group, true)
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

    if currentScan and currentScan.reason == ScanReason.Target
        and currentScan.playerGuid ~= currentTargetGuid then
        obsoletePlayerGuids[currentScan.playerGuid] = true
    end

    for playerGuid, reason in pairs(addon.queuedScanReasons or {}) do
        if reason == ScanReason.Target and playerGuid ~= currentTargetGuid then
            obsoletePlayerGuids[playerGuid] = true
        end
    end

    for playerGuid, retry in pairs(addon.delayedScanRetries or {}) do
        if retry.reason == ScanReason.Target and playerGuid ~= currentTargetGuid then
            obsoletePlayerGuids[playerGuid] = true
        end
    end

    return ReconcileObsoleteTargetWork(addon, obsoletePlayerGuids)
end

function ScanSession.CancelAutomaticGroupScans(addon)
    local affectedPlayerGuids = {}
    local currentScan = addon.currentScan

    if currentScan and currentScan.reason == ScanReason.Group then
        affectedPlayerGuids[currentScan.playerGuid] = true
    end

    for playerGuid, reason in pairs(addon.queuedScanReasons or {}) do
        if reason == ScanReason.Group then
            affectedPlayerGuids[playerGuid] = true
        end
    end

    for playerGuid, retryRecord in pairs(addon.delayedScanRetries or {}) do
        if retryRecord.reason == ScanReason.Group then
            affectedPlayerGuids[playerGuid] = true
        end
    end

    for _, retryRecord in pairs(addon.pendingRosterNameRetries or {}) do
        retryRecord.queueGroupScans = false
        retryRecord.forceFreshScans = false
    end

    local changed = false
    for playerGuid in pairs(affectedPlayerGuids) do
        addon:CancelManagedTimersForPlayer(playerGuid)
        if addon.delayedScanRetries then
            addon.delayedScanRetries[playerGuid] = nil
        end
        if addon.pendingRosterNameRetries then
            addon.pendingRosterNameRetries[playerGuid] = nil
        end
        addon:RemoveFromScanQueue(playerGuid)
        addon:ClearCurrentScanForPlayer(playerGuid)

        if addon.ClearPendingReportOffer then
            addon:ClearPendingReportOffer(playerGuid)
        end
        if addon.ClearPendingPublicScanAnnouncement then
            addon:ClearPendingPublicScanAnnouncement(playerGuid)
        end

        local playerInfo = addon.PlayerStore:Get(playerGuid)
        if playerInfo then
            if playerInfo.CheckStatus == ScanStatus.Successful then
                playerInfo.CheckRequested = false
                playerInfo.ForceScanRequested = false
                playerInfo.pendingChecks = 0
                playerInfo.ScanGeneration = (playerInfo.ScanGeneration or 0) + 1
            else
                addon.PlayerStore:MarkNotScanned(playerInfo)
            end
        end
        changed = true
    end

    addon:CancelScanQueueTimer()
    addon.UI:UpdateUI()

    if not InCombatLockdown() then
        addon:ProcessScanQueue()
    end

    return changed
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
    addon:ScheduleScanQueueProcessing(Constants.ScanInterval)

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

        if reason == ScanReason.Target and not addon:IsScanTargetAvailable(playerGuid, reason) then
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
    end, Constants.InspectReadyTimeout, playerGuid)
end

function ScanSession.RunChecks(addon, playerGuid, scanGeneration)
    local playerInfo = addon.db.global.PlayerGearInfo[playerGuid]
    if not addon:IsCurrentScan(playerGuid, scanGeneration) then
        return
    end

    if InCombatLockdown() then
        addon:PauseCurrentScanForCombat(playerGuid, scanGeneration)
        return
    end

    if not playerInfo or not playerInfo.CheckRequested then
        addon:FinishScan(playerGuid, scanGeneration, ScanStatus.Failed)
        return
    end

    if playerInfo.ScanGeneration ~= scanGeneration then
        return
    end

    if addon.currentScan.inspectReadyReceived then
        return
    end

    addon.currentScan.inspectReadyReceived = true
    playerInfo.CheckStatus = ScanStatus.InProgress
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
            status = ScanStatus.Partial
        else
            status = ScanStatus.Successful
        end

        local finished, finishedPlayerInfo, completedScan =
            addon:FinishScan(playerGuid, scanGeneration, status, {
                updateLastScanTime = true,
                debugMessage = "Scan completed for: " .. (updatedPlayerInfo.PlayerName or "Unknown"),
            })

        if finished then
            addon:MaybeSendReportOffer(finishedPlayerInfo, completedScan, status)
            addon:MaybeAnnouncePublicScanSummary(finishedPlayerInfo, completedScan, status)
        end

        if finished and status == ScanStatus.Partial and finishedPlayerInfo and completedScan then
            addon:ScheduleDelayedScanRetry(
                playerGuid,
                scanGeneration,
                completedScan.reason,
                ScanStatus.Partial,
                Constants.PartialScanRetryDelay
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
        addon:DeferCurrentScanUntilInspectable(playerGuid, scanGeneration)
        return
    end

    local playerInfo = addon.db.global.PlayerGearInfo[playerGuid]
    if not playerInfo or not playerInfo.CheckRequested then
        addon:FinishScan(playerGuid, scanGeneration, ScanStatus.Failed)
        return
    end

    if addon:IsPlayerScanComplete(playerInfo) and not playerInfo.ForceScanRequested then
        addon:FinishScan(playerGuid, scanGeneration, ScanStatus.Successful)
        return
    end

    if InCombatLockdown() then
        addon:PauseCurrentScanForCombat(playerGuid, scanGeneration)
        return
    end

    if playerInfo.CheckStatus == ScanStatus.Failed then
        addon:FinishScan(playerGuid, scanGeneration, ScanStatus.Failed)
        return
    end

    playerInfo.CheckStatus = ScanStatus.InProgress
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
        addon:DeferCurrentScanUntilInspectable(playerGuid, scanGeneration)
    end
end

function ScanSession.RetryInspection(addon, playerGuid, attempt, scanGeneration)
    local maxAttempts = Constants.InspectRetryMaxAttempts
    attempt = attempt or 1

    if not addon:IsCurrentScan(playerGuid, scanGeneration) then
        return
    end

    if InCombatLockdown() then
        addon:PauseCurrentScanForCombat(playerGuid, scanGeneration)
        return
    end

    if addon.currentScan.inspectReadyReceived then
        return
    end

    local reason = addon:NormalizeScanReason(addon.currentScan.reason)
    local playerInfo = addon.db.global.PlayerGearInfo[playerGuid]

    if not playerInfo or not playerInfo.CheckRequested then
        addon:FinishScan(playerGuid, scanGeneration, ScanStatus.Failed)
        return
    end

    if scanGeneration and playerInfo.ScanGeneration ~= scanGeneration then
        return
    end

    if not addon:IsScanTargetAvailable(playerGuid, reason) then
        if reason == ScanReason.Target then
            addon:OnPlayerTargetChanged()
            return
        end

        addon:FinishScan(playerGuid, scanGeneration, ScanStatus.Failed)
        return
    end

    local unitId = addon:GetScanUnitId(playerGuid, reason)
    if not addon:IsLocalPlayerGuid(playerGuid) and (not unitId or not CanInspect(unitId)) then
        addon:DeferCurrentScanUntilInspectable(playerGuid, scanGeneration)
        return
    end

    playerInfo.retryAttempts = playerInfo.retryAttempts or 0

    if playerInfo.retryAttempts >= maxAttempts then
        local finished, finishedPlayerInfo, completedScan =
            addon:FinishScan(playerGuid, scanGeneration, ScanStatus.TemporaryFailed)
        if finished and finishedPlayerInfo and completedScan then
            addon:ScheduleDelayedScanRetry(
                playerGuid,
                finishedPlayerInfo.ScanGeneration,
                completedScan.reason,
                ScanStatus.TemporaryFailed,
                Constants.TemporaryFailedScanRetryDelay
            )
        end
        return
    end

    playerInfo.retryAttempts = playerInfo.retryAttempts + 1
    addon:ScheduleManagedTimer(function()
        if not addon:IsCurrentScan(playerGuid, scanGeneration) then
            return
        end

        if InCombatLockdown() then
            addon:PauseCurrentScanForCombat(playerGuid, scanGeneration)
            return
        end

        if addon.currentScan.inspectReadyReceived then
            return
        end

        local currentPlayerInfo = addon.db.global.PlayerGearInfo[playerGuid]
        if not currentPlayerInfo or not currentPlayerInfo.CheckRequested then
            addon:FinishScan(playerGuid, scanGeneration, ScanStatus.Failed)
            return
        end

        if scanGeneration and currentPlayerInfo.ScanGeneration ~= scanGeneration then
            return
        end

        local currentUnitId = addon:GetScanUnitId(playerGuid, addon.currentScan.reason)
        if not currentUnitId then
            addon:DeferCurrentScanUntilInspectable(playerGuid, scanGeneration)
            return
        end

        addon:StartInspectionOfUnit(currentUnitId, addon.currentScan.reason, scanGeneration)
    end, Constants.ScanInterval * attempt, playerGuid)
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

function GearPolice:DeferCurrentScanUntilInspectable(playerGuid, scanGeneration)
    return ScanSession.DeferUntilInspectable(self, playerGuid, scanGeneration)
end

function GearPolice:PauseCurrentScanForCombat(playerGuid, scanGeneration)
    return ScanSession.PauseForCombat(self, playerGuid, scanGeneration)
end

function GearPolice:OnCombatStarted()
    return ScanSession.OnCombatStarted(self)
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

function GearPolice:CancelAutomaticGroupScans()
    return ScanSession.CancelAutomaticGroupScans(self)
end
