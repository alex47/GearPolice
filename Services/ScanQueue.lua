local GearPolice = GearPolice

GearPolice.ScanQueue = GearPolice.ScanQueue or {}

local ScanQueue = GearPolice.ScanQueue

local function RemoveQueueEntryAt(addon, index, playerGuid)
    table.remove(addon.scanQueue, index)
    if playerGuid then
        addon.queuedScanReasons[playerGuid] = nil
    end
end

local function FindNextInspectableEntry(addon)
    local index = 1

    while index <= #addon.scanQueue do
        local playerGuid = addon.scanQueue[index]
        local reason = addon.queuedScanReasons[playerGuid] or "group"

        if reason == "target" and not addon:IsScanTargetAvailable(playerGuid, reason) then
            addon:OnPlayerTargetChanged()
            return nil, nil, nil, nil, true
        end

        local playerInfo = addon.db.global.PlayerGearInfo[playerGuid]
        if not playerInfo then
            addon:SetPlayerGuidToDefaultInPlayerGearInfo(playerGuid)
            playerInfo = addon.db.global.PlayerGearInfo[playerGuid]
        end

        if not playerInfo then
            RemoveQueueEntryAt(addon, index, playerGuid)
        elseif addon:IsPlayerScanComplete(playerInfo) and not playerInfo.ForceScanRequested then
            playerInfo.CheckRequested = false
            RemoveQueueEntryAt(addon, index, playerGuid)
        elseif playerInfo.CheckStatus == "Failed" then
            playerInfo.CheckRequested = false
            RemoveQueueEntryAt(addon, index, playerGuid)
        else
            local unitId = addon:GetScanUnitId(playerGuid, reason)
            if unitId and (addon:IsLocalPlayerGuid(playerGuid) or CanInspect(unitId)) then
                return index, playerGuid, playerInfo, unitId, false
            end

            index = index + 1
        end
    end

    return nil, nil, nil, nil, false
end

function ScanQueue.CancelQueueTimer(addon)
    if not addon.scanQueueTimer then
        return
    end

    addon:CancelTimer(addon.scanQueueTimer)
    if addon.activeTimers then
        addon.activeTimers[addon.scanQueueTimer] = nil
    end
    addon.scanQueueTimer = nil
end

function ScanQueue.ScheduleProcessing(addon, delay)
    if addon.currentScan or #addon.scanQueue == 0 or addon.scanQueueTimer then
        return
    end

    addon.scanQueueTimer = addon:ScheduleManagedTimer(function()
        addon.scanQueueTimer = nil
        addon:ProcessScanQueue()
    end, delay or addon.scanInterval)
end

function ScanQueue.Process(addon)
    if addon.currentScan or #addon.scanQueue == 0 then return end

    if InCombatLockdown() then
        addon.Debug:Message("Scan queue paused while in combat.")
        return
    end

    addon:CancelScanQueueTimer()

    local queueIndex, playerGuid, playerInfo, unitId, targetChanged =
        FindNextInspectableEntry(addon)
    if targetChanged then
        return
    end

    if not playerGuid then
        addon:ScheduleScanQueueProcessing(addon.scanQueueAvailabilityInterval)
        return
    end

    local reason = addon.queuedScanReasons[playerGuid] or "group"
    RemoveQueueEntryAt(addon, queueIndex, playerGuid)

    playerInfo.CheckRequested = true
    playerInfo.CheckStatus = "InProgress"
    playerInfo.pendingChecks = 0
    playerInfo.retryAttempts = playerInfo.retryAttempts or 0

    local scanGeneration = playerInfo.ScanGeneration or 0
    addon.currentScan = {
        playerGuid = playerGuid,
        generation = scanGeneration,
        reason = reason,
    }
    addon.UI:UpdateUI()
    addon:StartInspectionOfUnit(unitId, reason, scanGeneration)
end

function ScanQueue.OnCombatEnded(addon)
    if addon.currentScan or #addon.scanQueue == 0 then return end

    addon.Debug:Message("Combat ended; resuming scan queue.")
    addon:ProcessScanQueue()
end

function ScanQueue.NormalizeReason(reason)
    if reason == "target" then
        return "target"
    end

    return "group"
end

function ScanQueue.Contains(addon, playerGuid)
    if not playerGuid then
        return false
    end

    for _, queuedGuid in ipairs(addon.scanQueue) do
        if queuedGuid == playerGuid then
            return true
        end
    end

    return false
end

function ScanQueue.HasScheduledPlayerWork(addon, playerGuid)
    local timers = addon.activePlayerTimers and addon.activePlayerTimers[playerGuid]
    return timers and next(timers) ~= nil
end

function ScanQueue.Add(addon, playerGuid, forceScan, reason, addToFront)
    if not playerGuid then return false end

    if addon.currentScan and addon.currentScan.playerGuid == playerGuid then
        return false
    end

    reason = addon:NormalizeScanReason(reason)
    if addon:IsPlayerQueued(playerGuid) then
        addon.queuedScanReasons[playerGuid] = reason

        if addon.db and addon.db.global and addon.db.global.PlayerGearInfo then
            local playerInfo = addon.db.global.PlayerGearInfo[playerGuid]
            if playerInfo then
                if forceScan then
                    playerInfo.ForceScanRequested = true
                end
            end
        end

        if addToFront then
            addon:RemoveFromScanQueue(playerGuid)
        else
            return false
        end
    end

    if addon.db and addon.db.global and addon.db.global.PlayerGearInfo then
        local playerInfo = addon.db.global.PlayerGearInfo[playerGuid]
        if playerInfo then
            if not forceScan and addon:IsPlayerScanComplete(playerInfo) then
                return false
            end

            playerInfo.ScanGeneration = (playerInfo.ScanGeneration or 0) + 1
            playerInfo.CheckRequested = true
            if forceScan then
                playerInfo.ForceScanRequested = true
            end
        end
    end

    addon.queuedScanReasons[playerGuid] = reason
    if addToFront then
        table.insert(addon.scanQueue, 1, playerGuid)
    else
        table.insert(addon.scanQueue, playerGuid)
    end

    return true
end

function ScanQueue.Remove(addon, playerGuid)
    if not playerGuid then
        return
    end

    for i = #addon.scanQueue, 1, -1 do
        if addon.scanQueue[i] == playerGuid then
            table.remove(addon.scanQueue, i)
        end
    end

    if addon.queuedScanReasons then
        addon.queuedScanReasons[playerGuid] = nil
    end
end

function GearPolice:CancelScanQueueTimer()
    return ScanQueue.CancelQueueTimer(self)
end

function GearPolice:ScheduleScanQueueProcessing(delay)
    return ScanQueue.ScheduleProcessing(self, delay)
end

function GearPolice:ProcessScanQueue()
    return ScanQueue.Process(self)
end

function GearPolice:OnCombatEnded()
    if self.SchedulePendingReportOffersAfterCombat then
        self:SchedulePendingReportOffersAfterCombat()
    end

    return ScanQueue.OnCombatEnded(self)
end

function GearPolice:NormalizeScanReason(reason)
    return ScanQueue.NormalizeReason(reason)
end

function GearPolice:IsPlayerQueued(playerGuid)
    return ScanQueue.Contains(self, playerGuid)
end

function GearPolice:HasScheduledPlayerWork(playerGuid)
    return ScanQueue.HasScheduledPlayerWork(self, playerGuid)
end

function GearPolice:AddToScanQueue(playerGuid, forceScan, reason, addToFront)
    return ScanQueue.Add(self, playerGuid, forceScan, reason, addToFront)
end

function GearPolice:RemoveFromScanQueue(playerGuid)
    return ScanQueue.Remove(self, playerGuid)
end
