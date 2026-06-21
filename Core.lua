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

function GearPolice:CancelScanQueueTimer()
    if not self.scanQueueTimer then
        return
    end

    self:CancelTimer(self.scanQueueTimer)
    if self.activeTimers then
        self.activeTimers[self.scanQueueTimer] = nil
    end
    self.scanQueueTimer = nil
end

function GearPolice:CreateEmptyRosterSnapshot(groupType)
    return {
        presentGuids = {},
        unitIdByGuid = {},
        sortIndexByGuid = {},
        orderedGuids = {},
        groupType = groupType,
    }
end

function GearPolice:ResetRosterSnapshot()
    self.currentRoster = self:CreateEmptyRosterSnapshot(nil)
end

function GearPolice:BuildGroupRosterSnapshot()
    local groupType, maxMembers
    if IsInRaid() then
        groupType = "raid"
        maxMembers = 40
    elseif IsInGroup() then
        groupType = "party"
        maxMembers = 4
    else
        return self:CreateEmptyRosterSnapshot(nil)
    end

    local snapshot = self:CreateEmptyRosterSnapshot(groupType)

    local function AddUnitToSnapshot(unitId, sortIndex)
        if not UnitExists(unitId) then
            return
        end

        local playerGuid = UnitGUID(unitId)
        if playerGuid and not snapshot.presentGuids[playerGuid] then
            snapshot.presentGuids[playerGuid] = true
            snapshot.unitIdByGuid[playerGuid] = unitId
            snapshot.sortIndexByGuid[playerGuid] = sortIndex
            table.insert(snapshot.orderedGuids, playerGuid)
        end
    end

    if groupType == "party" then
        AddUnitToSnapshot("player", 0)
    end

    for i = 1, maxMembers do
        AddUnitToSnapshot(groupType .. i, i)
    end

    return snapshot
end

function GearPolice:ApplyRosterMetadata(playerInfo, playerGuid, unitId, sortIndex, groupType)
    if not playerInfo then
        return
    end

    playerInfo.IsRosterTracked = true
    playerInfo.CurrentUnitId = unitId
    playerInfo.RosterSortIndex = sortIndex
    playerInfo.RosterGroupType = groupType
    playerInfo.PlayerGuid = playerGuid or playerInfo.PlayerGuid
end

function GearPolice:ClearRosterMetadata(playerInfo)
    if not playerInfo then
        return
    end

    playerInfo.IsRosterTracked = false
    playerInfo.CurrentUnitId = nil
    playerInfo.RosterSortIndex = nil
    playerInfo.RosterGroupType = nil
end

function GearPolice:RefreshCurrentRosterSnapshot()
    if IsInRaid() or IsInGroup() then
        self.currentRoster = self:BuildGroupRosterSnapshot()
    else
        self:ResetRosterSnapshot()
    end

    return self.currentRoster
end

function GearPolice:ApplyCurrentRosterMetadata(playerGuid, playerInfo)
    local roster = self.currentRoster
    if roster and roster.presentGuids and roster.presentGuids[playerGuid] then
        self:ApplyRosterMetadata(
            playerInfo,
            playerGuid,
            roster.unitIdByGuid[playerGuid],
            roster.sortIndexByGuid[playerGuid],
            roster.groupType
        )
    else
        self:ClearRosterMetadata(playerInfo)
    end
end

function GearPolice:RemoveGuidFromCurrentRoster(playerGuid)
    local roster = self.currentRoster
    if not playerGuid or not roster then
        return
    end

    if roster.presentGuids then
        roster.presentGuids[playerGuid] = nil
    end
    if roster.unitIdByGuid then
        roster.unitIdByGuid[playerGuid] = nil
    end
    if roster.sortIndexByGuid then
        roster.sortIndexByGuid[playerGuid] = nil
    end
    if roster.orderedGuids then
        for i = #roster.orderedGuids, 1, -1 do
            if roster.orderedGuids[i] == playerGuid then
                table.remove(roster.orderedGuids, i)
            end
        end
    end
end

function GearPolice:GetOrderedPlayerGuids()
    local orderedGuids = {}
    local includedGuids = {}

    if not self.db or not self.db.global or type(self.db.global.PlayerGearInfo) ~= "table" then
        return orderedGuids
    end

    local playerGearInfo = self.db.global.PlayerGearInfo
    local roster = self.currentRoster

    if roster and roster.orderedGuids then
        for _, playerGuid in ipairs(roster.orderedGuids) do
            if playerGearInfo[playerGuid] then
                table.insert(orderedGuids, playerGuid)
                includedGuids[playerGuid] = true
            end
        end
    end

    local nonRosterPlayers = {}
    for playerGuid, playerInfo in pairs(playerGearInfo) do
        if not includedGuids[playerGuid] then
            table.insert(nonRosterPlayers, {
                playerGuid = playerGuid,
                playerName = playerInfo.PlayerName or "Unknown",
            })
        end
    end

    table.sort(nonRosterPlayers, function(a, b)
        local nameA = string.lower(a.playerName or "")
        local nameB = string.lower(b.playerName or "")

        if nameA == nameB then
            return (a.playerGuid or "") < (b.playerGuid or "")
        end

        return nameA < nameB
    end)

    for _, player in ipairs(nonRosterPlayers) do
        table.insert(orderedGuids, player.playerGuid)
    end

    return orderedGuids
end

function GearPolice:ScheduleScanQueueProcessing(delay)
    if self.currentScan or #self.scanQueue == 0 or self.scanQueueTimer then
        return
    end

    self.scanQueueTimer = self:ScheduleManagedTimer(function()
        self.scanQueueTimer = nil
        self:ProcessScanQueue()
    end, delay or self.scanInterval)
end

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

    if type(GearPolice.db.global.PlayerGearInfo) ~= "table" then
        GearPolice.db.global.PlayerGearInfo = {}
    end

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

function GearPolice:ProcessScanQueue()
    if self.currentScan or #self.scanQueue == 0 then return end

    if InCombatLockdown() then
        self.Debug:Message("Scan queue paused while in combat.")
        return
    end

    self:CancelScanQueueTimer()

    while #self.scanQueue > 0 do
        local playerGuid = table.remove(self.scanQueue, 1)
        local reason = self.queuedScanReasons[playerGuid] or "group"
        self.queuedScanReasons[playerGuid] = nil

        if playerGuid then
            local playerInfo = self.db.global.PlayerGearInfo[playerGuid]
            if not playerInfo then
                self:SetPlayerGuidToDefaultInPlayerGearInfo(playerGuid)
                playerInfo = self.db.global.PlayerGearInfo[playerGuid]
            end

            if playerInfo then
                if self:IsPlayerScanComplete(playerInfo) and not playerInfo.ForceScanRequested then
                    playerInfo.CheckRequested = false
                elseif playerInfo.CheckStatus == "Failed" then
                    playerInfo.CheckRequested = false
                else
                    playerInfo.CheckRequested = true
                    playerInfo.CheckStatus = "InProgress"
                    playerInfo.pendingChecks = 0
                    playerInfo.retryAttempts = playerInfo.retryAttempts or 0

                    local scanGeneration = playerInfo.ScanGeneration or 0
                    self.currentScan = {
                        playerGuid = playerGuid,
                        generation = scanGeneration,
                        reason = reason,
                    }
                    self.activeScanGuids[playerGuid] = true
                    self.isScanning = true

                    local unitId = self:GetScanUnitId(playerGuid, reason)
                    if unitId then
                        self:StartInspectionOfUnit(unitId, reason, scanGeneration)
                    else
                        self:RetryInspection(playerGuid, 1, scanGeneration)
                    end
                    return
                end
            end
        end
    end
end

function GearPolice:OnCombatEnded()
    if self.currentScan or #self.scanQueue == 0 then return end

    self.Debug:Message("Combat ended; resuming scan queue.")
    self:ProcessScanQueue()
end

function GearPolice:NormalizeScanReason(reason)
    if reason == "target" then
        return "target"
    end

    return "group"
end

function GearPolice:IsPlayerQueued(playerGuid)
    if not playerGuid then
        return false
    end

    for _, queuedGuid in ipairs(self.scanQueue) do
        if queuedGuid == playerGuid then
            return true
        end
    end

    return false
end

function GearPolice:HasScheduledPlayerWork(playerGuid)
    local timers = self.activePlayerTimers and self.activePlayerTimers[playerGuid]
    return timers and next(timers) ~= nil
end

function GearPolice:AddToScanQueue(playerGuid, forceScan, reason, addToFront)
    if not playerGuid then return false end

    if self.currentScan and self.currentScan.playerGuid == playerGuid then
        return false
    end

    reason = self:NormalizeScanReason(reason)
    if self:IsPlayerQueued(playerGuid) then
        self.queuedScanReasons[playerGuid] = reason

        if self.db and self.db.global and self.db.global.PlayerGearInfo then
            local playerInfo = self.db.global.PlayerGearInfo[playerGuid]
            if playerInfo then
                playerInfo.QueuedScanReason = reason
                if forceScan then
                    playerInfo.ForceScanRequested = true
                end
            end
        end

        if addToFront then
            self:RemoveFromScanQueue(playerGuid)
        else
            return false
        end
    end

    if self.db and self.db.global and self.db.global.PlayerGearInfo then
        local playerInfo = self.db.global.PlayerGearInfo[playerGuid]
        if playerInfo then
            if not forceScan and self:IsPlayerScanComplete(playerInfo) then
                return false
            end

            playerInfo.ScanGeneration = (playerInfo.ScanGeneration or 0) + 1
            playerInfo.CheckRequested = true
            playerInfo.QueuedScanReason = reason
            if forceScan then
                playerInfo.ForceScanRequested = true
            end
        end
    end

    self.queuedScanReasons[playerGuid] = reason
    if addToFront then
        table.insert(GearPolice.scanQueue, 1, playerGuid)
    else
        table.insert(GearPolice.scanQueue, playerGuid)
    end

    return true
end

function GearPolice:RemoveFromScanQueue(playerGuid)
    if not playerGuid then
        return
    end

    for i = #self.scanQueue, 1, -1 do
        if self.scanQueue[i] == playerGuid then
            table.remove(self.scanQueue, i)
        end
    end

    if self.queuedScanReasons then
        self.queuedScanReasons[playerGuid] = nil
    end
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

    if self.db.global.PlayerGearInfo then
        self.db.global.PlayerGearInfo[playerGuid] = nil
    end

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

    if self.db and self.db.global and type(self.db.global.PlayerGearInfo) == "table" then
        for _, playerInfo in pairs(self.db.global.PlayerGearInfo) do
            playerInfo.CheckRequested = false
            playerInfo.CheckStatus = "Cancelled"
            playerInfo.pendingChecks = 0
            playerInfo.ScanGeneration = (playerInfo.ScanGeneration or 0) + 1
        end
    end
end

function GearPolice:ClearAllTrackedPlayers()
    self:StopAllScans()

    if self.db and self.db.global then
        self.db.global.PlayerGearInfo = {}
    end

    self:ResetRosterSnapshot()
    self.UI:UpdateUI()
end

function GearPolice:ClearTrackedPlayersForRosterTransition()
    self:StopAllScans()

    if self.db and self.db.global then
        self.db.global.PlayerGearInfo = {}
    end

    self:ResetRosterSnapshot()
end

function GearPolice:HasPendingEquippedItems(playerInfo)
    if not playerInfo or type(playerInfo.EquippedItems) ~= "table" then
        return true
    end

    for _, slotName in ipairs(self.Helper:GetInventorySlotNames()) do
        local slotValue = playerInfo.EquippedItems[slotName]
        if not slotValue or slotValue == self.InventorySlotPending then
            return true
        end
    end

    return false
end

function GearPolice:HasPendingItemMetadata(playerInfo)
    if not playerInfo or type(playerInfo.PendingItemMetadata) ~= "table" then
        return false
    end

    return next(playerInfo.PendingItemMetadata) ~= nil
end

function GearPolice:IsPlayerScanComplete(playerInfo)
    if not playerInfo then
        return false
    end

    if playerInfo.CheckStatus ~= "Successful" then
        return false
    end

    return not self:HasPendingEquippedItems(playerInfo)
        and not self:HasPendingItemMetadata(playerInfo)
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

function GearPolice:ReconcileGroupRoster(snapshot)
    if not snapshot or not snapshot.groupType then
        self:ClearAllTrackedPlayers()
        return
    end

    local playerGearInfo = self.db.global.PlayerGearInfo
    local removeGuids = {}

    for playerGuid, playerInfo in pairs(playerGearInfo) do
        if playerInfo.IsRosterTracked ~= false and not snapshot.presentGuids[playerGuid] then
            table.insert(removeGuids, playerGuid)
        end
    end

    for _, playerGuid in ipairs(removeGuids) do
        self:RemovePlayerFromTracking(playerGuid)
    end

    self.currentRoster = snapshot

    for _, playerGuid in ipairs(snapshot.orderedGuids) do
        local unitId = snapshot.unitIdByGuid[playerGuid]
        self:ProcessGroupMember(unitId, snapshot.sortIndexByGuid[playerGuid], snapshot.groupType)
    end

    self.UI:UpdateUI()
    self:ProcessScanQueue()
end

function GearPolice:UpdatePlayerGearInfoWithGroupMembers()
    local snapshot = self:BuildGroupRosterSnapshot()

    if not snapshot.groupType then
        self:ClearAllTrackedPlayers()
        self.wasGrouped = false
        return
    end

    if not self.wasGrouped then
        self:ClearTrackedPlayersForRosterTransition()
    end

    self.wasGrouped = true
    self:ReconcileGroupRoster(snapshot)
end

function GearPolice:ProcessGroupMember(unitId, sortIndex, groupType)
    if not UnitExists(unitId) then return end

    local playerGuid = UnitGUID(unitId)
    if not playerGuid then return end

    local playerName = UnitName(unitId)
    local playerInfo = self.db.global.PlayerGearInfo[playerGuid]

    if playerInfo then
        self:ApplyRosterMetadata(playerInfo, playerGuid, unitId, sortIndex, groupType)
    end

    if not playerName or playerName == "Unknown" then
        self:ScheduleManagedTimer(function()
            local roster = self.currentRoster
            local currentUnitId = roster and roster.unitIdByGuid and roster.unitIdByGuid[playerGuid]
            if currentUnitId and UnitGUID(currentUnitId) == playerGuid then
                self:ProcessGroupMember(
                    currentUnitId,
                    roster.sortIndexByGuid[playerGuid],
                    roster.groupType
                )
            end
        end, 1, playerGuid)
        return
    end

    local isNewPlayer = false
    if not playerInfo then
        self:SetPlayerGuidToDefaultInPlayerGearInfo(playerGuid)
        playerInfo = self.db.global.PlayerGearInfo[playerGuid]
        isNewPlayer = true
    end

    if not playerInfo then
        return
    end

    playerInfo.PlayerName = playerName
    self:ApplyRosterMetadata(playerInfo, playerGuid, unitId, sortIndex, groupType)

    if isNewPlayer then
        self:AddToScanQueue(playerGuid, true, "group")
    elseif playerInfo.CheckStatus == "TemporaryFailed" then
        if not self:HasScheduledPlayerWork(playerGuid) then
            playerInfo.CheckStatus = "InProgress"
            playerInfo.retryAttempts = 0
            self:AddToScanQueue(playerGuid, true, "group")
        end
    elseif playerInfo.CheckStatus == "Partial" then
        if not self:HasScheduledPlayerWork(playerGuid) then
            self:AddToScanQueue(playerGuid, true, "group")
        end
    elseif not playerInfo.LastScanTime or playerInfo.LastScanTime <= 0 then
        self:AddToScanQueue(playerGuid, true, "group")
    elseif (time() - playerInfo.LastScanTime) > 86400 then
        self:AddToScanQueue(playerGuid, true, "group")
    end
end

function GearPolice:ResetPlayerGearInfo(playerGuid, playerName)
    if not playerGuid then
        return
    end

    if not GearPolice.db.global.PlayerGearInfo[playerGuid] then
        self:SetPlayerGuidToDefaultInPlayerGearInfo(playerGuid)
    end

    local playerInfo = GearPolice.db.global.PlayerGearInfo[playerGuid]
    if not playerInfo then
        return
    end

    playerInfo.PlayerName = playerName or playerInfo.PlayerName or "Unknown"
    playerInfo.PlayerGuid = playerGuid
    playerInfo.CheckRequested = true
    playerInfo.CheckStatus = "InProgress"
    playerInfo.ProblematicItems = {}
    playerInfo.EquippedItems = {}
    playerInfo.PendingItemMetadata = {}
    playerInfo.LastScanTime = 0
    playerInfo.retryAttempts = 0
    playerInfo.pendingChecks = 0
    playerInfo.ForceScanRequested = true
    playerInfo.ScanGeneration = (playerInfo.ScanGeneration or 0) + 1
    self:ApplyCurrentRosterMetadata(playerGuid, playerInfo)

    self:ClearScheduledWorkForPlayer(playerGuid)
end

function GearPolice:SetPlayerGuidToDefaultInPlayerGearInfo(playerGuid)
    if not playerGuid then
        return
    end

    local _, _, _, _, _, playerName = GetPlayerInfoByGUID(playerGuid)

    GearPolice.db.global.PlayerGearInfo[playerGuid] = {
        ["PlayerName"] = playerName or "Unknown",
        ["PlayerGuid"] = playerGuid,
        ["CheckRequested"] = true,
        ["CheckStatus"] = "InProgress",
        ["ProblematicItems"] = {},
        ["PendingItemMetadata"] = {},
        ["LastScanTime"] = 0,
        ["retryAttempts"] = 0,
        ["ForceScanRequested"] = true,
        ["ScanGeneration"] = 0,
        ["IsRosterTracked"] = false
    }
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
