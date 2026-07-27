local GearPolice = GearPolice

local Inspection = GearPolice.Inspection
local Constants = GearPolice.Constants

local function InspectionRetryDelay()
    return Constants.InventorySlotRetryDelay
end

function Inspection:SetEquippedSlotValue(playerInfo, slotName, slotValue, scanGeneration)
    if not self:IsCurrentScan(playerInfo, scanGeneration) then
        return false
    end

    playerInfo.EquippedItems = playerInfo.EquippedItems or {}
    local currentValue = playerInfo.EquippedItems[slotName]

    if slotValue == Constants.InventorySlotPending then
        if not currentValue or currentValue == Constants.InventorySlotPending then
            playerInfo.EquippedItems[slotName] = slotValue
        end
        return true
    end

    if slotValue == Constants.InventorySlotEmpty then
        if not currentValue
            or currentValue == Constants.InventorySlotPending
            or currentValue == Constants.InventorySlotEmpty then
            playerInfo.EquippedItems[slotName] = slotValue
        end
        return true
    end

    playerInfo.EquippedItems[slotName] = slotValue
    return true
end

function Inspection:GetCapturedInventoryEvidenceCount(playerInfo, excludedSlotName)
    if not playerInfo or type(playerInfo.EquippedItems) ~= "table" then
        return 0
    end

    local evidenceCount = 0
    for _, slotName in ipairs(GearPolice.Slots.GetInventorySlotNames()) do
        if slotName ~= excludedSlotName and self:IsStoredItemLink(playerInfo.EquippedItems[slotName]) then
            evidenceCount = evidenceCount + 1
        end
    end

    return evidenceCount
end

function Inspection:CanConfirmEmptyInventorySlot(playerInfo, unitId, slotName, noEvidenceCount)
    if GearPolice.Inventory:CanConfirmEmptyInventorySlot(unitId, slotName, noEvidenceCount) then
        return true
    end

    if (noEvidenceCount or 0) < Constants.InventorySlotEmptyConfirmations then
        return false
    end

    local capturedEvidenceCount = self:GetCapturedInventoryEvidenceCount(playerInfo, slotName)
    return capturedEvidenceCount >= Constants.InventorySnapshotEvidenceMinimum
end

function Inspection:ResolveInventorySlotWithRetry(
    playerInfo,
    slotName,
    retryCount,
    onResolved,
    noEvidenceCount,
    scanGeneration
)
    if not self:IsCurrentScan(playerInfo, scanGeneration) then
        return
    end

    if InCombatLockdown() then
        GearPolice:PauseCurrentScanForCombat(playerInfo.PlayerGuid, scanGeneration)
        return
    end

    local targetReason = GearPolice.Constants.ScanReason.Target
    local currentScan = GearPolice.currentScan
    if currentScan and currentScan.reason == targetReason
        and not GearPolice:IsScanTargetAvailable(playerInfo.PlayerGuid, targetReason) then
        GearPolice:OnPlayerTargetChanged()
        return
    end

    if not retryCount then
        retryCount = Constants.InventorySlotRetryCount
    end

    if not noEvidenceCount then
        noEvidenceCount = 0
    end

    local unitId = GearPolice.Units.GetUnitIdOfPlayerGuid(playerInfo.PlayerGuid)
    local slotState, itemLink, slotID
    if unitId then
        slotState, itemLink, slotID = GearPolice.Inventory:GetInventorySlotState(unitId, slotName)
    else
        slotState = Constants.InventorySlotPending
    end

    if slotState == Constants.InventorySlotReady then
        if not self:SetEquippedSlotValue(playerInfo, slotName, itemLink, scanGeneration) then
            return
        end
        onResolved(slotName, itemLink, slotID)
        return
    end

    if slotState == Constants.InventorySlotNoEvidence then
        noEvidenceCount = noEvidenceCount + 1
        if self:CanConfirmEmptyInventorySlot(playerInfo, unitId, slotName, noEvidenceCount) then
            if not self:SetEquippedSlotValue(
                playerInfo,
                slotName,
                Constants.InventorySlotEmpty,
                scanGeneration
            ) then
                return
            end
            onResolved(slotName, Constants.InventorySlotEmpty, slotID)
            return
        end
    else
        noEvidenceCount = 0
    end

    if retryCount <= 0 then
        if not self:SetEquippedSlotValue(
            playerInfo,
            slotName,
            Constants.InventorySlotPending,
            scanGeneration
        ) then
            return
        end
        GearPolice.Debug:Message("Unable to confirm " .. slotName .. " for " .. playerInfo.PlayerName)
        onResolved(slotName, Constants.InventorySlotPending, slotID)
        return
    end

    local delay = InspectionRetryDelay()
    GearPolice:ScheduleManagedTimer(function()
        Inspection:ResolveInventorySlotWithRetry(
            playerInfo,
            slotName,
            retryCount - 1,
            onResolved,
            noEvidenceCount,
            scanGeneration
        )
    end, delay, playerInfo.PlayerGuid)
end
