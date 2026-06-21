local GearPolice = GearPolice

GearPolice.Inventory = GearPolice.Inventory or {}
GearPolice.Helper = GearPolice.Helper or {}

local Inventory = GearPolice.Inventory
local Helper = GearPolice.Helper

function Inventory.GetInventorySlotNames()
    return GearPolice.Slots.GetInventorySlotNames()
end

function Inventory:InventorySlotTooltipHasItem(unitId, slotID)
    if not unitId or not slotID or not UnitExists(unitId) then
        return false
    end

    if not self.inventoryProbeTooltip then
        self.inventoryProbeTooltip = CreateFrame(
            "GameTooltip",
            "GearPoliceInventoryProbeTooltip",
            UIParent,
            "GameTooltipTemplate"
        )
    end

    local tooltip = self.inventoryProbeTooltip
    tooltip:ClearLines()
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")

    local hasItem = tooltip:SetInventoryItem(unitId, slotID)
    tooltip:Hide()

    return hasItem and true or false
end

function Inventory:GetInventorySlotState(unitId, slotName)
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

function Inventory:IsInventorySlotEvidenceState(slotState)
    return slotState == GearPolice.InventorySlotReady or slotState == GearPolice.InventorySlotPending
end

function Inventory:GetInventorySnapshotEvidenceCount(unitId, excludedSlotName)
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

function Inventory:CanConfirmEmptyInventorySlot(unitId, slotName, noEvidenceCount)
    if (noEvidenceCount or 0) < GearPolice.InventorySlotEmptyConfirmations then
        return false
    end

    return self:GetInventorySnapshotEvidenceCount(unitId, slotName) >= GearPolice.InventorySnapshotEvidenceMinimum
end

function Helper.GetInventorySlotNames()
    return Inventory.GetInventorySlotNames()
end

function Helper:InventorySlotTooltipHasItem(unitId, slotID)
    return Inventory:InventorySlotTooltipHasItem(unitId, slotID)
end

function Helper:GetInventorySlotState(unitId, slotName)
    return Inventory:GetInventorySlotState(unitId, slotName)
end

function Helper:IsInventorySlotEvidenceState(slotState)
    return Inventory:IsInventorySlotEvidenceState(slotState)
end

function Helper:GetInventorySnapshotEvidenceCount(unitId, excludedSlotName)
    return Inventory:GetInventorySnapshotEvidenceCount(unitId, excludedSlotName)
end

function Helper:CanConfirmEmptyInventorySlot(unitId, slotName, noEvidenceCount)
    return Inventory:CanConfirmEmptyInventorySlot(unitId, slotName, noEvidenceCount)
end
