GearPolice = LibStub("AceAddon-3.0"):NewAddon("GearPolice", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

GearPolice:RegisterChatCommand("gearpolice", "HandleSlashCommands")

GearPolice.scanQueue = {}
GearPolice.isScanning = false
GearPolice.scanInterval = 2  -- Time between scans in seconds
GearPolice.maxConcurrentScans = 5
GearPolice.activeTimers = {}
GearPolice.InventorySlotReady = "READY"
GearPolice.InventorySlotPending = "PENDING"
GearPolice.InventorySlotNoEvidence = "NO_EVIDENCE"
GearPolice.InventorySlotEmpty = "EMPTY"
GearPolice.InventorySlotRetryCount = 6
GearPolice.InventorySlotRetryDelay = 2
GearPolice.InventorySlotEmptyConfirmations = 5
GearPolice.InventorySnapshotEvidenceMinimum = 4

function GearPolice:ScheduleManagedTimer(callback, delay)
    if type(callback) ~= "function" or not delay then
        return nil
    end

    self.activeTimers = self.activeTimers or {}

    local handle
    handle = self:ScheduleTimer(function()
        if self.activeTimers then
            self.activeTimers[handle] = nil
        end
        callback()
    end, delay)

    if handle then
        self.activeTimers[handle] = true
    end

    return handle
end

function GearPolice:CancelAllManagedTimers()
    if not self.activeTimers then
        return
    end

    for handle in pairs(self.activeTimers) do
        self:CancelTimer(handle, true)
    end

    self.activeTimers = {}
end

function GearPolice:OnInitialize()
    GearPolice:Print("Addon loaded!")

    GearPolice.db = LibStub("AceDB-3.0"):New("GearPoliceDB")

    self.activeTimers = {}

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

    -- Track active scans to avoid overlap
    local activeScans = {}
    local processed = 0

    -- Process up to maxConcurrentScans players
    for _ = 1, math.min(self.maxConcurrentScans, #self.scanQueue) do
        local playerGuid = table.remove(self.scanQueue, 1)  -- FIFO
        if playerGuid then
            table.insert(activeScans, playerGuid)
            processed = processed + 1
        end
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

function GearPolice:AddToScanQueue(playerGuid)
    if not playerGuid then return end

    if self.db and self.db.global and self.db.global.PlayerGearInfo then
        local playerInfo = self.db.global.PlayerGearInfo[playerGuid]
        if playerInfo then
            playerInfo.CheckRequested = true
        end
    end

    if not tContains(GearPolice.scanQueue, playerGuid) then
        table.insert(GearPolice.scanQueue, playerGuid)
    end
end

function GearPolice:StopAllScans()
    self:CancelAllManagedTimers()

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end

    self.scanQueue = {}
    self.isScanning = false

    if self.db and self.db.global and type(self.db.global.PlayerGearInfo) == "table" then
        for _, playerInfo in pairs(self.db.global.PlayerGearInfo) do
            playerInfo.CheckRequested = false
            playerInfo.CheckStatus = "Cancelled"
            playerInfo.pendingChecks = 0
        end
    end
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

function GearPolice:UpdatePlayerEquippedItems(unitId, onComplete)
    local playerGuid = UnitGUID(unitId)
    if not playerGuid then
        if onComplete then
            onComplete(true)
        end
        return
    end

    local playerInfo = self.db.global.PlayerGearInfo[playerGuid]
    if not playerInfo then
        self:SetPlayerGuidToDefaultInPlayerGearInfo(playerGuid)
        playerInfo = self.db.global.PlayerGearInfo[playerGuid]
    end

    playerInfo.EquippedItems = playerInfo.EquippedItems or {}
    local slotOrder = self.Helper:GetInventorySlotNames()
    local pendingCount = #slotOrder
    local anyPending = false

    for _, slotName in ipairs(slotOrder) do
        GearPolice:UpdatePlayerEquippedItemForSlot(unitId, slotName, self.InventorySlotRetryCount, function(slotState, itemLink)
            if slotState == self.InventorySlotReady then
                playerInfo.EquippedItems[slotName] = itemLink
            elseif slotState == self.InventorySlotEmpty then
                playerInfo.EquippedItems[slotName] = self.InventorySlotEmpty
            else
                local existingItemLink = playerInfo.EquippedItems[slotName]
                if not existingItemLink
                    or existingItemLink == self.InventorySlotPending
                    or existingItemLink == self.InventorySlotEmpty then
                    playerInfo.EquippedItems[slotName] = self.InventorySlotPending
                    anyPending = true
                end
            end
            pendingCount = pendingCount - 1
            
            --GearPolice.UI:UpdateUI()

            if pendingCount == 0 and onComplete then
                onComplete(anyPending)
            end
        end, 0, playerGuid)
    end
end

function GearPolice:UpdatePlayerEquippedItemForSlot(unitId, slotName, retryCount, onComplete, noEvidenceCount, expectedPlayerGuid)
    retryCount = retryCount or self.InventorySlotRetryCount
    noEvidenceCount = noEvidenceCount or 0

    if expectedPlayerGuid and UnitGUID(unitId) ~= expectedPlayerGuid then
        onComplete(self.InventorySlotPending)
        return
    end

    local slotState, itemLink = self.Helper:GetInventorySlotState(unitId, slotName)
    if slotState == self.InventorySlotReady then
        onComplete(slotState, itemLink)
        return
    end

    if slotState == self.InventorySlotNoEvidence then
        noEvidenceCount = noEvidenceCount + 1
        if self.Helper:CanConfirmEmptyInventorySlot(unitId, slotName, noEvidenceCount) then
            onComplete(self.InventorySlotEmpty)
            return
        end
    else
        noEvidenceCount = 0
    end

    if retryCount > 0 then
        self:ScheduleManagedTimer(function()
            GearPolice:UpdatePlayerEquippedItemForSlot(unitId, slotName, retryCount - 1, onComplete, noEvidenceCount, expectedPlayerGuid)
        end, self.InventorySlotRetryDelay)
    else
        onComplete(self.InventorySlotPending)
    end
end

function GearPolice:ProcessGroupMember(unitId)
    if not UnitExists(unitId) then return end

    local playerGuid = UnitGUID(unitId)
    local playerName = UnitName(unitId)

    if not playerName or playerName == "Unknown" then
        self:ScheduleManagedTimer(function()
            self:ProcessGroupMember(unitId)
        end, 1)
        return
    end

    if not self.db.global.PlayerGearInfo[playerGuid] then
        self:SetPlayerGuidToDefaultInPlayerGearInfo(playerGuid)
    end

    local playerInfo = self.db.global.PlayerGearInfo[playerGuid]
    
    -- Update equipped items (with retry logic) for this unit.
    self:UpdatePlayerEquippedItems(unitId)

    if playerInfo.CheckStatus == "TemporaryFailed" then
        playerInfo.CheckStatus = "InProgress"
        playerInfo.retryAttempts = 0
        self:AddToScanQueue(playerGuid)
    end

    if playerInfo.CheckStatus == "Partial" then
        self:AddToScanQueue(playerGuid)
    end

    if (playerInfo.LastScanTime and (time() - playerInfo.LastScanTime) > 86400) then
        self:AddToScanQueue(playerGuid)
    end

    self.UI:UpdateUI()
end

function GearPolice:ResetPlayerGearInfo(playerGuid)
    if GearPolice.db.global.PlayerGearInfo[playerGuid] then
        GearPolice.db.global.PlayerGearInfo[playerGuid].CheckRequested = true
        GearPolice.db.global.PlayerGearInfo[playerGuid].CheckStatus = "InProgress"
        GearPolice.db.global.PlayerGearInfo[playerGuid].ProblematicItems = {}
        GearPolice.db.global.PlayerGearInfo[playerGuid].LastScanTime = 0
    end
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
        ["retryAttempts"] = 0
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

    if InCombatLockdown() then
        self.Debug:Message("Cannot inspect in combat; queued scan for later.")
        self:AddToScanQueue(playerGuid)
        return
    end

    -- Skip if already failed (optional)
    if playerInfo.CheckStatus == "Failed" then return end

    playerInfo.CheckRequested = true
    playerInfo.CheckStatus = "InProgress"

    if CanInspect(unitId) then
        NotifyInspect(unitId)
        self.UI:UpdatePlayerStatusIcon(playerGuid, "scanning")
    else
        -- Trigger retry with attempt tracking
        self:RetryInspection(playerGuid, 1)
    end
end

function GearPolice:RetryInspection(playerGuid, attempt)
    local maxAttempts = 5  -- Increased retries
    local playerInfo = self.db.global.PlayerGearInfo[playerGuid]

    -- Check if player is still in the group
    if not self.Helper:IsPlayerInGroup(playerGuid) then
        -- Permanent failure (player left)
        playerInfo.CheckStatus = "Failed"
        self.UI:UpdatePlayerStatusIcon(playerGuid, "failed")
        return
    end

    if not playerInfo.retryAttempts then
        playerInfo.retryAttempts = 0
    end

    -- Temporary failure (retry later)
    if playerInfo.retryAttempts >= maxAttempts then
        playerInfo.CheckStatus = "TemporaryFailed"
        self.UI:UpdatePlayerStatusIcon(playerGuid, "temporary_failed")
        -- Requeue after 5 minutes
        self:ScheduleManagedTimer(function()
            playerInfo.retryAttempts = 0
            self:AddToScanQueue(playerGuid)
        end, 300)
        return
    end

    -- Increment attempts and retry
    playerInfo.retryAttempts = playerInfo.retryAttempts + 1
    self:ScheduleManagedTimer(function()
        local unitId = self.Helper:GetUnitIdOfPlayerGuid(playerGuid)
        if unitId then
            self:StartInspectionOfUnit(unitId)
        else
            self:RetryInspection(playerGuid, attempt + 1)
        end
    end, self.scanInterval * attempt)
end

function GearPolice:StartGearPolicingOfGroup()
    GearPolice:UpdatePlayerGearInfoWithGroupMembers()
    GearPolice:ProcessScanQueue()
end

function GearPolice:StartGearPolicingOfTarget()
    local targetGuid = UnitGUID("target")
    if targetGuid then
        GearPolice:ProcessGroupMember("target")
        GearPolice.UI:UpdateUI()

        GearPolice:ProcessScanQueue()
        GearPolice.UI:UpdateUI()
    end
end

function GearPolice:OnInspectReady(eventName, playerGuid)
    if not playerGuid then return end

    local playerInfo = GearPolice.db.global.PlayerGearInfo[playerGuid]
    if not playerInfo or not playerInfo.CheckRequested then
        self.isScanning = false
        return
    end

    playerInfo.CheckStatus = "InProgress"
    playerInfo.EquippedItems = {}
    GearPolice.UI:UpdateUI()

    -- Start the unit check (which will run per-slot checks for gems/enchants, etc.)
    GearPolice.Inspection:CheckUnit(playerInfo, function(updatedPlayerInfo)
        updatedPlayerInfo.CheckRequested = false
        updatedPlayerInfo.retryAttempts = 0

        -- Now update the equipped items—with retries per slot.
        -- (Assuming here that we can get the unit id; you may need to store it earlier.)
        local unitId = GearPolice.Helper:GetUnitIdOfPlayerGuid(playerGuid)
        if unitId then
            GearPolice:UpdatePlayerEquippedItems(unitId, function(anyPending)
                if anyPending then
                    updatedPlayerInfo.CheckStatus = "Partial"  -- Not all slots have valid item links.
                    -- Schedule a follow-up scan after a delay (e.g. 60 seconds)
                    self:ScheduleManagedTimer(function()
                        self:AddToScanQueue(playerGuid)
                        GearPolice.UI:UpdateUI()
                    end, 60)
                else
                    updatedPlayerInfo.CheckStatus = "Successful"
                end
                updatedPlayerInfo.LastScanTime = time()
                GearPolice.Debug:Message("Scan completed for: " .. updatedPlayerInfo.PlayerName)
                GearPolice.UI:UpdateUI()
                self:ScheduleManagedTimer(function()
                    GearPolice:ProcessScanQueue()
                end, GearPolice.scanInterval)
            end)
        else
            updatedPlayerInfo.CheckStatus = "Failed"
            GearPolice.UI:UpdateUI()
        end
    end)
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
