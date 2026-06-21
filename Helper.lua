local GearPolice = GearPolice

GearPolice.Helper = GearPolice.Helper or {}
local Helper = GearPolice.Helper

function Helper.GetInventorySlotNames()
    return GearPolice.Slots.GetInventorySlotNames()
end

function Helper:InventorySlotTooltipHasItem(unitId, slotID)
    if not unitId or not slotID or not UnitExists(unitId) then
        return false
    end

    if not self.inventoryProbeTooltip then
        self.inventoryProbeTooltip = CreateFrame("GameTooltip", "GearPoliceInventoryProbeTooltip", UIParent, "GameTooltipTemplate")
    end

    local tooltip = self.inventoryProbeTooltip
    tooltip:ClearLines()
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")

    local hasItem = tooltip:SetInventoryItem(unitId, slotID)
    tooltip:Hide()

    return hasItem and true or false
end

function Helper:GetInventorySlotState(unitId, slotName)
    if not unitId or not slotName or not UnitExists(unitId) then
        return GearPolice.InventorySlotPending
    end

    local slotID = GetInventorySlotInfo(slotName)
    if not slotID then
        return GearPolice.InventorySlotNoEvidence
    end

    local itemLink = GetInventoryItemLink(unitId, slotID)
    if itemLink then
        return GearPolice.InventorySlotReady, itemLink, slotID
    end

    local itemID
    if GetInventoryItemID then
        itemID = GetInventoryItemID(unitId, slotID)
    end

    local texture = GetInventoryItemTexture(unitId, slotID)
    local hasTooltipItem = self:InventorySlotTooltipHasItem(unitId, slotID)

    if itemID or texture or hasTooltipItem then
        return GearPolice.InventorySlotPending, nil, slotID, itemID, texture, hasTooltipItem
    end

    return GearPolice.InventorySlotNoEvidence, nil, slotID
end

function Helper:IsInventorySlotEvidenceState(slotState)
    return slotState == GearPolice.InventorySlotReady or slotState == GearPolice.InventorySlotPending
end

function Helper:GetInventorySnapshotEvidenceCount(unitId, excludedSlotName)
    if not unitId or not UnitExists(unitId) then
        return 0
    end

    local evidenceCount = 0
    for _, slotName in ipairs(GearPolice.Slots.GetInventorySnapshotEvidenceSlotNames()) do
        if slotName ~= excludedSlotName then
            local slotState = self:GetInventorySlotState(unitId, slotName)
            if self:IsInventorySlotEvidenceState(slotState) then
                evidenceCount = evidenceCount + 1
            end
        end
    end

    return evidenceCount
end

function Helper:CanConfirmEmptyInventorySlot(unitId, slotName, noEvidenceCount)
    if (noEvidenceCount or 0) < GearPolice.InventorySlotEmptyConfirmations then
        return false
    end

    return self:GetInventorySnapshotEvidenceCount(unitId, slotName) >= GearPolice.InventorySnapshotEvidenceMinimum
end

function Helper:GetUnitIdOfPlayerGuid(playerGuid)
    if UnitGUID("player") == playerGuid then
        return "player"
    end

    if UnitGUID("target") == playerGuid then
        return "target"
    end

    local roster = GearPolice.currentRoster
    if roster and roster.unitIdByGuid then
        local unitId = roster.unitIdByGuid[playerGuid]
        if unitId and UnitGUID(unitId) == playerGuid then
            return unitId
        end
    end

    if IsInRaid() then
        for i = 1, 40 do
            local unitId = "raid" .. i
            local playerGuid2 = UnitGUID(unitId)

            if (playerGuid == playerGuid2) then
                return unitId
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local unitId = "party" .. i
            local playerGuid2 = UnitGUID(unitId)

            if (playerGuid == playerGuid2) then
                return unitId
            end
        end
    end

    return nil
end

function Helper:tContains(table, value)
    for _, v in pairs(table) do
        if v == value then return true end
    end
    return false
end

function Helper:IsPlayerInGroup(playerGuid)
    -- Check raid
    if IsInRaid() then
        for i = 1, 40 do
            local unitId = "raid" .. i
            if UnitExists(unitId) and UnitGUID(unitId) == playerGuid then
                return true
            end
        end
    -- Check party
    elseif IsInGroup() then
        for i = 1, 4 do
            local unitId = "party" .. i
            if UnitExists(unitId) and UnitGUID(unitId) == playerGuid then
                return true
            end
        end
    end

    -- Check player themselves
    return UnitGUID("player") == playerGuid
end
