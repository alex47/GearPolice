GearPolice = LibStub("AceAddon-3.0"):NewAddon("GearPolice", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

GearPolice:RegisterChatCommand("gearpolice", "HandleSlashCommands")

GearPolice.scanQueue = {}
GearPolice.queuedScanReasons = {}
GearPolice.currentScan = nil
GearPolice.scanQueueTimer = nil
GearPolice.isScanning = false
GearPolice.activeScanGuids = {}
GearPolice.activeTimers = {}
GearPolice.activePlayerTimers = {}
GearPolice.currentRoster = nil
GearPolice.wasGrouped = false

function GearPolice:OnInitialize()
    GearPolice:Print("Addon loaded!")

    GearPolice.db = LibStub("AceDB-3.0"):New("GearPoliceDB")

    self.activeScanGuids = {}
    self.activeTimers = {}
    self.activePlayerTimers = {}
    self.queuedScanReasons = {}
    self.currentScan = nil
    self.scanQueueTimer = nil
    self.isScanning = false
    self.wasGrouped = IsInRaid() or IsInGroup()
    self:ResetRosterSnapshot()

    self.PlayerStore:EnsureStorage()

    if GearPolice.db.global.ReportMode ~= "whisper"
        and GearPolice.db.global.ReportMode ~= "public"
        and GearPolice.db.global.ReportMode ~= "debug" then
        GearPolice.db.global.ReportMode = "whisper"
    end

    -- Initialize DebugEnabled if it's not set
    if type(GearPolice.db.global.DebugEnabled) ~= "boolean" then
        GearPolice.db.global.DebugEnabled = false
    end
end

function GearPolice:OnEnable()
    self:RegisterEvent("INSPECT_READY", "OnInspectReady")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "UpdateGroupMembers")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")
end

function GearPolice:ClearCurrentScanForPlayer(playerGuid)
    if not playerGuid or not self.currentScan or self.currentScan.playerGuid ~= playerGuid then
        return
    end

    self.currentScan = nil
    self.isScanning = false
    if self.activeScanGuids then
        self.activeScanGuids[playerGuid] = nil
    end

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end
end

function GearPolice:ClearScheduledWorkForPlayer(playerGuid)
    if not playerGuid then
        return
    end

    self:CancelManagedTimersForPlayer(playerGuid)
    self:RemoveFromScanQueue(playerGuid)
    self:ClearCurrentScanForPlayer(playerGuid)
end

function GearPolice:RemovePlayerFromTracking(playerGuid)
    if not playerGuid or not self.db or not self.db.global then
        return
    end

    self:ClearScheduledWorkForPlayer(playerGuid)

    self.PlayerStore:Remove(playerGuid)

    self:RemoveGuidFromCurrentRoster(playerGuid)
end

function GearPolice:StopAllScans()
    self:CancelAllManagedTimers()

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end

    self.scanQueue = {}
    self.queuedScanReasons = {}
    self.currentScan = nil
    self.activeScanGuids = {}
    self.isScanning = false
    self.scanQueueTimer = nil
    self:ResetRosterSnapshot()

    self.PlayerStore:MarkAllScansCancelled()
end

function GearPolice:ClearAllTrackedPlayers()
    self:StopAllScans()

    self.PlayerStore:ClearAll()

    self:ResetRosterSnapshot()
    self.UI:UpdateUI()
end

function GearPolice:ClearTrackedPlayersForRosterTransition()
    self:StopAllScans()

    self.PlayerStore:ClearAll()

    self:ResetRosterSnapshot()
end

function GearPolice:IsCurrentScan(playerGuid, scanGeneration)
    local currentScan = self.currentScan
    if not currentScan or currentScan.playerGuid ~= playerGuid then
        return false
    end

    if scanGeneration and currentScan.generation ~= scanGeneration then
        return false
    end

    return true
end

function GearPolice:IsScanTargetAvailable(playerGuid, reason)
    if not playerGuid then
        return false
    end

    reason = self:NormalizeScanReason(reason)
    if reason == "target" then
        return UnitGUID("target") == playerGuid
    end

    return self.Helper:IsPlayerInGroup(playerGuid)
end

function GearPolice:GetScanUnitId(playerGuid, reason)
    reason = self:NormalizeScanReason(reason)
    if not self:IsScanTargetAvailable(playerGuid, reason) then
        return nil
    end

    if reason == "target" then
        return "target"
    end

    return self.Helper:GetUnitIdOfPlayerGuid(playerGuid)
end

function GearPolice:IsLocalPlayerGuid(playerGuid)
    return playerGuid and UnitGUID("player") == playerGuid
end

function GearPolice:FinishScan(playerGuid, scanGeneration, status, options)
    if not self:IsCurrentScan(playerGuid, scanGeneration) then
        return false
    end

    options = options or {}

    local currentScan = self.currentScan
    local playerInfo = self.db.global.PlayerGearInfo[playerGuid]
    if playerInfo and scanGeneration and playerInfo.ScanGeneration ~= scanGeneration then
        return false
    end

    self:CancelManagedTimersForPlayer(playerGuid)
    self:RemoveFromScanQueue(playerGuid)

    if self.activeScanGuids then
        self.activeScanGuids[playerGuid] = nil
    end
    self.currentScan = nil
    self.isScanning = false

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
        self.Debug:Message(options.debugMessage)
    end

    self.UI:UpdateUI()
    self:ScheduleScanQueueProcessing(self.scanInterval)

    return true, playerInfo, currentScan
end

function GearPolice:ScheduleDelayedScanRetry(playerGuid, scanGeneration, reason, expectedStatus, delay)
    reason = self:NormalizeScanReason(reason)

    self:ScheduleManagedTimer(function()
        local playerInfo = self.db.global.PlayerGearInfo[playerGuid]
        if not playerInfo then
            return
        end

        if playerInfo.ScanGeneration ~= scanGeneration or playerInfo.CheckStatus ~= expectedStatus then
            return
        end

        if not self:IsScanTargetAvailable(playerGuid, reason) then
            return
        end

        playerInfo.retryAttempts = 0
        self:AddToScanQueue(playerGuid, true, reason)
        self.UI:UpdateUI()
        self:ProcessScanQueue()
    end, delay, playerGuid)
end

function GearPolice:ScheduleInspectReadyTimeout(playerGuid, scanGeneration)
    self:ScheduleManagedTimer(function()
        if not self:IsCurrentScan(playerGuid, scanGeneration) then
            return
        end

        if self.currentScan.inspectReadyReceived then
            return
        end

        self.Debug:Message("INSPECT_READY timed out; retrying scan.")
        self:RetryInspection(playerGuid, 1, scanGeneration)
    end, self.inspectReadyTimeout, playerGuid)
end

function GearPolice:RunInspectionChecks(playerGuid, scanGeneration)
    local playerInfo = GearPolice.db.global.PlayerGearInfo[playerGuid]
    if not self:IsCurrentScan(playerGuid, scanGeneration) then
        return
    end

    if not playerInfo or not playerInfo.CheckRequested then
        self:FinishScan(playerGuid, scanGeneration, "Failed")
        return
    end

    if playerInfo.ScanGeneration ~= scanGeneration then
        return
    end

    if self.currentScan.inspectReadyReceived then
        return
    end

    self.currentScan.inspectReadyReceived = true
    playerInfo.CheckStatus = "InProgress"
    playerInfo.EquippedItems = {}
    GearPolice.UI:UpdateUI()

    GearPolice.Inspection:CheckUnit(playerInfo, function(updatedPlayerInfo)
        if not self:IsCurrentScan(playerGuid, scanGeneration)
            or updatedPlayerInfo.ScanGeneration ~= scanGeneration then
            return
        end

        local status
        if GearPolice:HasPendingEquippedItems(updatedPlayerInfo)
            or GearPolice:HasPendingItemMetadata(updatedPlayerInfo) then
            status = "Partial"
        else
            status = "Successful"
        end

        local finished, finishedPlayerInfo, completedScan =
            self:FinishScan(playerGuid, scanGeneration, status, {
                updateLastScanTime = true,
                debugMessage = "Scan completed for: " .. (updatedPlayerInfo.PlayerName or "Unknown"),
            })

        if finished and status == "Partial" and finishedPlayerInfo and completedScan then
            self:ScheduleDelayedScanRetry(
                playerGuid,
                scanGeneration,
                completedScan.reason,
                "Partial",
                60
            )
        end
    end, scanGeneration)
end

function GearPolice:StartInspectionOfUnit(unitId, reason, scanGeneration)
    if not self.currentScan then
        return
    end

    reason = self:NormalizeScanReason(reason or self.currentScan.reason)
    local playerGuid = self.currentScan.playerGuid

    if not self:IsCurrentScan(playerGuid, scanGeneration) then
        return
    end

    if not unitId or not UnitExists(unitId) or UnitGUID(unitId) ~= playerGuid then
        self:RetryInspection(playerGuid, 1, scanGeneration)
        return
    end

    local playerInfo = self.db.global.PlayerGearInfo[playerGuid]
    if not playerInfo or not playerInfo.CheckRequested then
        self:FinishScan(playerGuid, scanGeneration, "Failed")
        return
    end

    if self:IsPlayerScanComplete(playerInfo) and not playerInfo.ForceScanRequested then
        self:FinishScan(playerGuid, scanGeneration, "Successful")
        return
    end

    if InCombatLockdown() then
        self.Debug:Message("Cannot inspect in combat; queued scan for later.")
        self:ClearCurrentScanForPlayer(playerGuid)
        self:AddToScanQueue(playerGuid, true, reason, true)
        return
    end

    if playerInfo.CheckStatus == "Failed" then
        self:FinishScan(playerGuid, scanGeneration, "Failed")
        return
    end

    playerInfo.CheckStatus = "InProgress"
    self.currentScan.unitId = unitId
    self.currentScan.reason = reason
    self.currentScan.inspectReadyReceived = false
    self.activeScanGuids[playerGuid] = true

    if self:IsLocalPlayerGuid(playerGuid) then
        self.UI:UpdatePlayerStatusIcon(playerGuid, "scanning")
        self:RunInspectionChecks(playerGuid, scanGeneration)
        return
    end

    if CanInspect(unitId) then
        NotifyInspect(unitId)
        self:ScheduleInspectReadyTimeout(playerGuid, scanGeneration)
        self.UI:UpdatePlayerStatusIcon(playerGuid, "scanning")
    else
        self:RetryInspection(playerGuid, 1, scanGeneration)
    end
end

function GearPolice:RetryInspection(playerGuid, attempt, scanGeneration)
    local maxAttempts = 5
    attempt = attempt or 1

    if not self:IsCurrentScan(playerGuid, scanGeneration) then
        return
    end

    if self.currentScan.inspectReadyReceived then
        return
    end

    local reason = self:NormalizeScanReason(self.currentScan.reason)
    local playerInfo = self.db.global.PlayerGearInfo[playerGuid]

    if not playerInfo or not playerInfo.CheckRequested then
        self:FinishScan(playerGuid, scanGeneration, "Failed")
        return
    end

    if scanGeneration and playerInfo.ScanGeneration ~= scanGeneration then
        return
    end

    if not self:IsScanTargetAvailable(playerGuid, reason) then
        self:FinishScan(playerGuid, scanGeneration, "Failed")
        return
    end

    playerInfo.retryAttempts = playerInfo.retryAttempts or 0

    if playerInfo.retryAttempts >= maxAttempts then
        local finished, finishedPlayerInfo, completedScan =
            self:FinishScan(playerGuid, scanGeneration, "TemporaryFailed")
        if finished and finishedPlayerInfo and completedScan then
            self:ScheduleDelayedScanRetry(
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
    self:ScheduleManagedTimer(function()
        if not self:IsCurrentScan(playerGuid, scanGeneration) then
            return
        end

        if self.currentScan.inspectReadyReceived then
            return
        end

        local currentPlayerInfo = self.db.global.PlayerGearInfo[playerGuid]
        if not currentPlayerInfo or not currentPlayerInfo.CheckRequested then
            self:FinishScan(playerGuid, scanGeneration, "Failed")
            return
        end

        if scanGeneration and currentPlayerInfo.ScanGeneration ~= scanGeneration then
            return
        end

        local unitId = self:GetScanUnitId(playerGuid, self.currentScan.reason)
        if unitId then
            self:StartInspectionOfUnit(unitId, self.currentScan.reason, scanGeneration)
        else
            self:RetryInspection(playerGuid, attempt + 1, scanGeneration)
        end
    end, self.scanInterval * attempt, playerGuid)
end

function GearPolice:StartGearPolicingOfGroup()
    GearPolice:UpdatePlayerGearInfoWithGroupMembers()
end

function GearPolice:StartGearPolicingOfTarget()
    local targetGuid = UnitGUID("target")
    if targetGuid then
        local targetName = UnitName("target")
        if not targetName or targetName == "Unknown" then
            self:ScheduleManagedTimer(function()
                if UnitGUID("target") == targetGuid then
                    self:StartGearPolicingOfTarget()
                end
            end, 1, targetGuid)
            return
        end

        GearPolice:RefreshCurrentRosterSnapshot()
        GearPolice:ResetPlayerGearInfo(targetGuid, targetName)
        GearPolice:AddToScanQueue(targetGuid, true, "target", true)
        GearPolice.UI:UpdateUI()

        GearPolice:ProcessScanQueue()
        GearPolice.UI:UpdateUI()
    end
end

function GearPolice:OnInspectReady(eventName, playerGuid)
    if not playerGuid then return end

    if not self:IsCurrentScan(playerGuid) then
        return
    end

    local scanGeneration = self.currentScan.generation
    self:RunInspectionChecks(playerGuid, scanGeneration)
end

function GearPolice:UpdateGroupMembers()
    GearPolice:UpdatePlayerGearInfoWithGroupMembers()
end

-- Slash command

function GearPolice:HandleSlashCommands(msg, editbox)
    if (msg == "target") then
        GearPolice:StartGearPolicingOfTarget()
    elseif (msg == "showui") then
        GearPolice.UI:ShowUI()
    elseif (msg == "debug") then
        GearPolice.db.global.DebugEnabled = not GearPolice.db.global.DebugEnabled
        GearPolice:Print("Debug mode " .. (GearPolice.db.global.DebugEnabled and "enabled" or "disabled") .. ".")
    else
        -- Start scanning group when no argument is provided
        GearPolice:StartGearPolicingOfGroup()
    end
end
