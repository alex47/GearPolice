local GearPolice = GearPolice

local Inspection = GearPolice.Inspection

local function InspectionRetryDelay()
    return GearPolice.InventorySlotRetryDelay
end

function Inspection:SetEquippedSlotValue(playerInfo, slotName, slotValue, scanGeneration)
    if not self:IsCurrentScan(playerInfo, scanGeneration) then
        return false
    end

    playerInfo.EquippedItems = playerInfo.EquippedItems or {}
    local currentValue = playerInfo.EquippedItems[slotName]

    if slotValue == GearPolice.InventorySlotPending then
        if not currentValue or currentValue == GearPolice.InventorySlotPending then
            playerInfo.EquippedItems[slotName] = slotValue
        end
        return true
    end

    if slotValue == GearPolice.InventorySlotEmpty then
        if not currentValue
            or currentValue == GearPolice.InventorySlotPending
            or currentValue == GearPolice.InventorySlotEmpty then
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
    for _, slotName in ipairs(GearPolice.Helper:GetInventorySlotNames()) do
        if slotName ~= excludedSlotName and self:IsStoredItemLink(playerInfo.EquippedItems[slotName]) then
            evidenceCount = evidenceCount + 1
        end
    end

    return evidenceCount
end

function Inspection:CanConfirmEmptyInventorySlot(playerInfo, unitId, slotName, noEvidenceCount)
    if GearPolice.Helper:CanConfirmEmptyInventorySlot(unitId, slotName, noEvidenceCount) then
        return true
    end

    if (noEvidenceCount or 0) < GearPolice.InventorySlotEmptyConfirmations then
        return false
    end

    local capturedEvidenceCount = self:GetCapturedInventoryEvidenceCount(playerInfo, slotName)
    return capturedEvidenceCount >= GearPolice.InventorySnapshotEvidenceMinimum
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

    local currentScan = GearPolice.currentScan
    if currentScan and currentScan.reason == "target"
        and not GearPolice:IsScanTargetAvailable(playerInfo.PlayerGuid, "target") then
        GearPolice:OnPlayerTargetChanged()
        return
    end

    if not retryCount then
        retryCount = GearPolice.InventorySlotRetryCount
    end

    if not noEvidenceCount then
        noEvidenceCount = 0
    end

    local unitId = GearPolice.Helper:GetUnitIdOfPlayerGuid(playerInfo.PlayerGuid)
    local slotState, itemLink, slotID
    if unitId then
        slotState, itemLink, slotID = GearPolice.Helper:GetInventorySlotState(unitId, slotName)
    else
        slotState = GearPolice.InventorySlotPending
    end

    if slotState == GearPolice.InventorySlotReady then
        if not self:SetEquippedSlotValue(playerInfo, slotName, itemLink, scanGeneration) then
            return
        end
        onResolved(slotName, itemLink, slotID)
        return
    end

    if slotState == GearPolice.InventorySlotNoEvidence then
        noEvidenceCount = noEvidenceCount + 1
        if self:CanConfirmEmptyInventorySlot(playerInfo, unitId, slotName, noEvidenceCount) then
            if not self:SetEquippedSlotValue(
                playerInfo,
                slotName,
                GearPolice.InventorySlotEmpty,
                scanGeneration
            ) then
                return
            end
            onResolved(slotName, GearPolice.InventorySlotEmpty, slotID)
            return
        end
    else
        noEvidenceCount = 0
    end

    if retryCount <= 0 then
        if not self:SetEquippedSlotValue(
            playerInfo,
            slotName,
            GearPolice.InventorySlotPending,
            scanGeneration
        ) then
            return
        end
        GearPolice.Debug:Message("Unable to confirm " .. slotName .. " for " .. playerInfo.PlayerName)
        onResolved(slotName, GearPolice.InventorySlotPending, slotID)
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
