local GearPolice = GearPolice

local Inspection = GearPolice.Inspection

function Inspection:IsItemInfoAvailable(itemLink)
    if not itemLink then
        return false
    end

    local itemName = GetItemInfo(itemLink)
    return itemName ~= nil
end

function Inspection:CountSocketSlots(itemLink)
    if not itemLink then
        return 0
    end

    local tempTable = {}
    local itemStats = GetItemStats(itemLink, tempTable)

    if not itemStats then
        if not self:IsItemInfoAvailable(itemLink) then
            return GearPolice.ItemMetadataPending
        end

        return 0
    end

    local socketSlotCount = 0
    for label, value in pairs(itemStats) do
        if label:match("EMPTY_SOCKET_") then
            socketSlotCount = socketSlotCount + (tonumber(value) or 1)
        end
    end

    return socketSlotCount
end

function Inspection:CountSocketedGemIds(itemLink, maxGemFields)
    if not itemLink then
        return 0
    end

    maxGemFields = maxGemFields or 4
    if maxGemFields > 4 then
        maxGemFields = 4
    end

    local itemString = itemLink:match("item:([^|]+)")
    if not itemString then
        return 0
    end

    local _, _, gemId1, gemId2, gemId3, gemId4 = strsplit(":", itemString)
    local gemIds = { gemId1, gemId2, gemId3, gemId4 }
    local socketedGemCount = 0

    for i = 1, maxGemFields do
        local gemId = gemIds[i]
        if gemId and gemId ~= "" and gemId ~= "0" then
            socketedGemCount = socketedGemCount + 1
        end
    end

    return socketedGemCount
end

function Inspection:IsItemMissingGems(itemLink)
    if not itemLink then
        return false
    end

    local socketSlotCount = self:CountSocketSlots(itemLink)

    if self:IsItemMetadataPending(socketSlotCount) then
        return GearPolice.ItemMetadataPending
    end

    if socketSlotCount == 0 then
        return false
    end

    if socketSlotCount > 4 then
        return GearPolice.ItemMetadataPending
    end

    local socketedGemCount = self:CountSocketedGemIds(itemLink, socketSlotCount)
    return socketedGemCount < socketSlotCount
end

function Inspection:IsItemMissingEnchant(itemLink)
    if not itemLink then
        return false
    end

    local enchantID = select(3, strsplit(":", itemLink))

    return (not enchantID) or enchantID == "" or enchantID == "0"
end

function Inspection:IsItemBelowItemLevel(itemLink)
    if not itemLink then
        return false
    end

    local itemLevel, _, _ = GetDetailedItemLevelInfo(itemLink)

    if not itemLevel then
        return GearPolice.ItemMetadataPending
    end

    return itemLevel < GearPolice.ItemLevelThreshold
end

function Inspection:IsWaistMissingExtraGemEnchant(itemLink)
    if not itemLink then return false end

    local base = self:CountSocketSlots(itemLink)
    if self:IsItemMetadataPending(base) then
        return GearPolice.ItemMetadataPending
    end

    if base == 0 then return false end

    local inserted = self:CountSocketedGemIds(itemLink, 4)

    if inserted < base then return false end
    if inserted == base then return true end
    return false
end

function Inspection:IsItemMissingUpgrade(itemLink, unitId, slotID)
    -- Short-circuit upgrade checks; treat every item as fully upgraded.
    return false
end

function Inspection:IsTwoHandedOrRangedWeaponLink(itemLink)
    if not itemLink then
        return false
    end

    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    if not equipLoc then
        return GearPolice.ItemMetadataPending
    end

    return equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_RANGED"
end
