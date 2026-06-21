local GearPolice = GearPolice

GearPolice.Inspection = GearPolice.Inspection or {}

local Inspection = GearPolice.Inspection

function Inspection:IsCurrentScan(playerInfo, scanGeneration)
    return not scanGeneration or (playerInfo and playerInfo.ScanGeneration == scanGeneration)
end

function Inspection:IsStoredItemLink(slotValue)
    if not slotValue then
        return false
    end

    if slotValue == GearPolice.InventorySlotPending then
        return false
    end

    if slotValue == GearPolice.InventorySlotEmpty then
        return false
    end

    if slotValue == GearPolice.InventorySlotNoEvidence then
        return false
    end

    if slotValue == GearPolice.InventorySlotReady then
        return false
    end

    return true
end

function Inspection:IsItemMetadataPending(checkResult)
    return checkResult == GearPolice.ItemMetadataPending
end

function Inspection:MarkItemMetadataPending(playerInfo, slotName, itemLink, scanGeneration)
    if not self:IsCurrentScan(playerInfo, scanGeneration) then
        return false
    end

    playerInfo.PendingItemMetadata = playerInfo.PendingItemMetadata or {}
    playerInfo.PendingItemMetadata[slotName] = itemLink or true
    return true
end

function Inspection:RecordProblem(playerInfo, slotName, itemLink, ruleId, message, scanGeneration)
    if not self:IsCurrentScan(playerInfo, scanGeneration) then
        return false
    end

    if type(playerInfo) ~= "table" or type(itemLink) ~= "string" or type(message) ~= "string" then
        return false
    end

    playerInfo.Problems = playerInfo.Problems or {}
    table.insert(playerInfo.Problems, {
        slotName = slotName,
        itemLink = itemLink,
        ruleId = ruleId,
        message = message,
    })

    playerInfo.ProblematicItems = playerInfo.ProblematicItems or {}
    playerInfo.ProblematicItems[itemLink] = playerInfo.ProblematicItems[itemLink] or {}
    table.insert(playerInfo.ProblematicItems[itemLink], message)

    return true
end
