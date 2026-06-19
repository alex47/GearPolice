GearPolice = LibStub("AceAddon-3.0"):NewAddon("GearPolice", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

GearPolice:RegisterChatCommand("gearpolice", "HandleSlashCommands")

GearPolice.scanQueue = {}
GearPolice.isScanning = false
GearPolice.scanInterval = 2  -- Time between scans in seconds
GearPolice.maxConcurrentScans = 5
GearPolice.activeScanGuids = {}
GearPolice.activeTimers = {}
GearPolice.activePlayerTimers = {}
GearPolice.InventorySlotReady = "READY"
GearPolice.InventorySlotPending = "PENDING"
GearPolice.InventorySlotNoEvidence = "NO_EVIDENCE"
GearPolice.InventorySlotEmpty = "EMPTY"
GearPolice.InventorySlotRetryCount = 6
GearPolice.InventorySlotRetryDelay = 2
GearPolice.InventorySlotEmptyConfirmations = 5
GearPolice.InventorySnapshotEvidenceMinimum = 4

function GearPolice:ScheduleManagedTimer(callback, delay, playerGuid)
    if type(callback) ~= "function" or not delay then
        return nil
    end

    self.activeTimers = self.activeTimers or {}
    self.activePlayerTimers = self.activePlayerTimers or {}

    local handle
    handle = self:ScheduleTimer(function()
        if self.activeTimers then
            self.activeTimers[handle] = nil
        end
        if playerGuid and self.activePlayerTimers and self.activePlayerTimers[playerGuid] then
            self.activePlayerTimers[playerGuid][handle] = nil
            if not next(self.activePlayerTimers[playerGuid]) then
                self.activePlayerTimers[playerGuid] = nil
            end
        end
        callback()
    end, delay)

    if handle then
        self.activeTimers[handle] = playerGuid or true
        if playerGuid then
            self.activePlayerTimers[playerGuid] = self.activePlayerTimers[playerGuid] or {}
            self.activePlayerTimers[playerGuid][handle] = true
        end
    end

    return handle
end

function GearPolice:CancelManagedTimersForPlayer(playerGuid)
    if not playerGuid or not self.activePlayerTimers then
        return
    end

    local timers = self.activePlayerTimers[playerGuid]
    if not timers then
        return
    end

    for handle in pairs(timers) do
        self:CancelTimer(handle)
        if self.activeTimers then
            self.activeTimers[handle] = nil
        end
    end

    self.activePlayerTimers[playerGuid] = nil
end

function GearPolice:CancelAllManagedTimers()
    if not self.activeTimers then
        return
    end

    for handle in pairs(self.activeTimers) do
        self:CancelTimer(handle, true)
    end

    self.activeTimers = {}
    self.activePlayerTimers = {}
end

function GearPolice:OnInitialize()
    GearPolice:Print("Addon loaded!")

    GearPolice.db = LibStub("AceDB-3.0"):New("GearPoliceDB")

    self.activeScanGuids = {}
    self.activeTimers = {}
    self.activePlayerTimers = {}

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
    if self.isScanning or #self.scanQueue == 0 then return end

    if InCombatLockdown() then
        self.Debug:Message("Scan queue paused while in combat.")
        return
    end

    self.isScanning = true

    local activeScans = {}

    -- Process up to maxConcurrentScans players, skipping GUIDs already being inspected.
    while #activeScans < self.maxConcurrentScans and #self.scanQueue > 0 do
        local playerGuid = table.remove(self.scanQueue, 1)  -- FIFO
        if playerGuid and not self.activeScanGuids[playerGuid] then
            table.insert(activeScans, playerGuid)
        end
    end

    if #activeScans == 0 then
        self.isScanning = false
        return
    end

    -- Start inspections for this batch
    for _, playerGuid in ipairs(activeScans) do
        local unitId = self.Helper:GetUnitIdOfPlayerGuid(playerGuid)
        if unitId then
            self:StartInspectionOfUnit(unitId)
        else
            -- Requeue if unitID not found
            self:AddToScanQueue(playerGuid)
        end
    end

    -- Schedule next batch only after this one completes
    self:ScheduleManagedTimer(function()
        self.isScanning = false
        self:ProcessScanQueue()
    end, self.scanInterval)
end

function GearPolice:OnCombatEnded()
    if #self.scanQueue == 0 then return end

    self.isScanning = false
    self.Debug:Message("Combat ended; resuming scan queue.")
    self:ProcessScanQueue()
end

function GearPolice:AddToScanQueue(playerGuid, forceScan)
    if not playerGuid then return false end

    if self.activeScanGuids and self.activeScanGuids[playerGuid] then
        return false
    end

    if tContains(GearPolice.scanQueue, playerGuid) then
        return false
    end

    if self.db and self.db.global and self.db.global.PlayerGearInfo then
        local playerInfo = self.db.global.PlayerGearInfo[playerGuid]
        if playerInfo then
            if not forceScan and self:IsPlayerScanComplete(playerInfo) then
                return false
            end

            if not playerInfo.CheckRequested then
                playerInfo.ScanGeneration = (playerInfo.ScanGeneration or 0) + 1
            end
            playerInfo.CheckRequested = true
            if forceScan then
                playerInfo.ForceScanRequested = true
            end
        end
    end

    table.insert(GearPolice.scanQueue, playerGuid)
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
end

function GearPolice:ClearScheduledWorkForPlayer(playerGuid)
    if not playerGuid then
        return
    end

    self:CancelManagedTimersForPlayer(playerGuid)
    self:RemoveFromScanQueue(playerGuid)
    if self.activeScanGuids then
        self.activeScanGuids[playerGuid] = nil
    end
end

function GearPolice:StopAllScans()
    self:CancelAllManagedTimers()

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end

    self.scanQueue = {}
    self.activeScanGuids = {}
    self.isScanning = false

    if self.db and self.db.global and type(self.db.global.PlayerGearInfo) == "table" then
        for _, playerInfo in pairs(self.db.global.PlayerGearInfo) do
            playerInfo.CheckRequested = false
            playerInfo.CheckStatus = "Cancelled"
            playerInfo.pendingChecks = 0
            playerInfo.ScanGeneration = (playerInfo.ScanGeneration or 0) + 1
        end
    end
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

function GearPolice:IsPlayerScanComplete(playerInfo)
    if not playerInfo then
        return false
    end

    if playerInfo.CheckStatus ~= "Successful" then
        return false
    end

    return not self:HasPendingEquippedItems(playerInfo)
end

function GearPolice:UpdatePlayerGearInfoWithGroupMembers()
    local groupType, maxMembers
    if IsInRaid() then
        groupType = "raid"
        maxMembers = 40
    elseif IsInGroup() then
        groupType = "party"
        maxMembers = 4
    else
        return
    end

    for i = 1, maxMembers do
        local unitId = groupType .. i

        if UnitExists(unitId) then
            GearPolice:ProcessGroupMember(unitId)
        end
    end
end

function GearPolice:ProcessGroupMember(unitId)
    if not UnitExists(unitId) then return end

    local playerGuid = UnitGUID(unitId)
    local playerName = UnitName(unitId)
    local isNewPlayer = false

    if not playerName or playerName == "Unknown" then
        self:ScheduleManagedTimer(function()
            self:ProcessGroupMember(unitId)
        end, 1, playerGuid)
        return
    end

    if not self.db.global.PlayerGearInfo[playerGuid] then
        self:SetPlayerGuidToDefaultInPlayerGearInfo(playerGuid)
        isNewPlayer = true
    end

    local playerInfo = self.db.global.PlayerGearInfo[playerGuid]

    if isNewPlayer then
        self:AddToScanQueue(playerGuid, true)
    elseif playerInfo.CheckStatus == "TemporaryFailed" then
        playerInfo.CheckStatus = "InProgress"
        playerInfo.retryAttempts = 0
        self:AddToScanQueue(playerGuid, true)
    elseif playerInfo.CheckStatus == "Partial" then
        self:AddToScanQueue(playerGuid, true)
    elseif not playerInfo.LastScanTime or playerInfo.LastScanTime <= 0 then
        self:AddToScanQueue(playerGuid, true)
    elseif (time() - playerInfo.LastScanTime) > 86400 then
        self:AddToScanQueue(playerGuid, true)
    end

    self.UI:UpdateUI()
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
    playerInfo.LastScanTime = 0
    playerInfo.retryAttempts = 0
    playerInfo.pendingChecks = 0
    playerInfo.ForceScanRequested = true
    playerInfo.ScanGeneration = (playerInfo.ScanGeneration or 0) + 1

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
        ["LastScanTime"] = 0,
        ["retryAttempts"] = 0,
        ["ForceScanRequested"] = true,
        ["ScanGeneration"] = 0
    }
end

function GearPolice:StartInspectionOfUnit(unitId)
    if not UnitExists(unitId) then
        self.isScanning = false
        return
    end

    local playerGuid = UnitGUID(unitId)
    if not playerGuid then
        self.isScanning = false
        return
    end

    local playerInfo = self.db.global.PlayerGearInfo[playerGuid]

    if not playerInfo then
        self:SetPlayerGuidToDefaultInPlayerGearInfo(playerGuid)
        playerInfo = self.db.global.PlayerGearInfo[playerGuid]
    end

    if not playerInfo then return end

    if not playerInfo.CheckRequested then
        self:ClearScheduledWorkForPlayer(playerGuid)
        return
    end

    if self:IsPlayerScanComplete(playerInfo) and not playerInfo.ForceScanRequested then
        playerInfo.CheckRequested = false
        self:ClearScheduledWorkForPlayer(playerGuid)
        return
    end

    if InCombatLockdown() then
        self.Debug:Message("Cannot inspect in combat; queued scan for later.")
        self:AddToScanQueue(playerGuid, true)
        return
    end

    -- Skip if already failed (optional)
    if playerInfo.CheckStatus == "Failed" then
        self:ClearScheduledWorkForPlayer(playerGuid)
        return
    end

    playerInfo.CheckStatus = "InProgress"
    self.activeScanGuids[playerGuid] = true
    local scanGeneration = playerInfo.ScanGeneration or 0

    if CanInspect(unitId) then
        playerInfo.ForceScanRequested = false
        NotifyInspect(unitId)
        self.UI:UpdatePlayerStatusIcon(playerGuid, "scanning")
    else
        -- Trigger retry with attempt tracking
        self:RetryInspection(playerGuid, 1, scanGeneration)
    end
end

function GearPolice:RetryInspection(playerGuid, attempt, scanGeneration)
    local maxAttempts = 5  -- Increased retries
    local playerInfo = self.db.global.PlayerGearInfo[playerGuid]

    if not playerInfo or not playerInfo.CheckRequested then
        self:ClearScheduledWorkForPlayer(playerGuid)
        return
    end

    if scanGeneration and playerInfo.ScanGeneration ~= scanGeneration then
        return
    end

    -- Check if player is still in the group
    if not self.Helper:IsPlayerInGroup(playerGuid) then
        -- Permanent failure (player left)
        playerInfo.CheckStatus = "Failed"
        self:ClearScheduledWorkForPlayer(playerGuid)
        self.UI:UpdatePlayerStatusIcon(playerGuid, "failed")
        return
    end

    if not playerInfo.retryAttempts then
        playerInfo.retryAttempts = 0
    end

    -- Temporary failure (retry later)
    if playerInfo.retryAttempts >= maxAttempts then
        playerInfo.CheckStatus = "TemporaryFailed"
        self.activeScanGuids[playerGuid] = nil
        self.UI:UpdatePlayerStatusIcon(playerGuid, "temporary_failed")
        -- Requeue after 5 minutes
        local retryGeneration = playerInfo.ScanGeneration
        self:ScheduleManagedTimer(function()
            if playerInfo.ScanGeneration == retryGeneration and playerInfo.CheckStatus == "TemporaryFailed" then
                playerInfo.retryAttempts = 0
                self:AddToScanQueue(playerGuid, true)
            end
        end, 300, playerGuid)
        return
    end

    -- Increment attempts and retry
    playerInfo.retryAttempts = playerInfo.retryAttempts + 1
    self:ScheduleManagedTimer(function()
        local currentPlayerInfo = self.db.global.PlayerGearInfo[playerGuid]
        if not currentPlayerInfo or not currentPlayerInfo.CheckRequested then
            self:ClearScheduledWorkForPlayer(playerGuid)
            return
        end

        if scanGeneration and currentPlayerInfo.ScanGeneration ~= scanGeneration then
            return
        end

        local unitId = self.Helper:GetUnitIdOfPlayerGuid(playerGuid)
        if unitId then
            self:StartInspectionOfUnit(unitId)
        else
            self:RetryInspection(playerGuid, attempt + 1, scanGeneration)
        end
    end, self.scanInterval * attempt, playerGuid)
end

function GearPolice:StartGearPolicingOfGroup()
    GearPolice:UpdatePlayerGearInfoWithGroupMembers()
    GearPolice:ProcessScanQueue()
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

        GearPolice:ResetPlayerGearInfo(targetGuid, targetName)
        GearPolice:AddToScanQueue(targetGuid, true)
        GearPolice.UI:UpdateUI()

        GearPolice:ProcessScanQueue()
        GearPolice.UI:UpdateUI()
    end
end

function GearPolice:OnInspectReady(eventName, playerGuid)
    if not playerGuid then return end

    local playerInfo = GearPolice.db.global.PlayerGearInfo[playerGuid]
    if not self.activeScanGuids[playerGuid] then
        return
    end

    if not playerInfo or not playerInfo.CheckRequested then
        self.activeScanGuids[playerGuid] = nil
        self.isScanning = false
        return
    end

    playerInfo.CheckStatus = "InProgress"
    playerInfo.ScanGeneration = (playerInfo.ScanGeneration or 0) + 1
    local scanGeneration = playerInfo.ScanGeneration
    playerInfo.EquippedItems = {}
    GearPolice.UI:UpdateUI()

    GearPolice.Inspection:CheckUnit(playerInfo, function(updatedPlayerInfo)
        if updatedPlayerInfo.ScanGeneration ~= scanGeneration then
            return
        end

        updatedPlayerInfo.CheckRequested = false
        updatedPlayerInfo.retryAttempts = 0
        self:ClearScheduledWorkForPlayer(playerGuid)

        if GearPolice:HasPendingEquippedItems(updatedPlayerInfo) then
            updatedPlayerInfo.CheckStatus = "Partial"
            self:ScheduleManagedTimer(function()
                if updatedPlayerInfo.ScanGeneration == scanGeneration
                    and updatedPlayerInfo.CheckStatus == "Partial" then
                    self:AddToScanQueue(playerGuid, true)
                    GearPolice.UI:UpdateUI()
                end
            end, 60, playerGuid)
        else
            updatedPlayerInfo.CheckStatus = "Successful"
        end

        updatedPlayerInfo.LastScanTime = time()
        updatedPlayerInfo.ForceScanRequested = false
        GearPolice.Debug:Message("Scan completed for: " .. updatedPlayerInfo.PlayerName)
        GearPolice.UI:UpdateUI()
        self:ScheduleManagedTimer(function()
            GearPolice:ProcessScanQueue()
        end, GearPolice.scanInterval)
    end, scanGeneration)
end

function GearPolice:UpdateGroupMembers()
    GearPolice:UpdatePlayerGearInfoWithGroupMembers()
    GearPolice:ProcessScanQueue()  -- Start scanning new/updated players
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
