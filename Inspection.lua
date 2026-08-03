local GearPolice = GearPolice

GearPolice.Inspection = GearPolice.Inspection or {}

local Inspection = GearPolice.Inspection
local Constants = GearPolice.Constants

function Inspection:IsCurrentScan(playerInfo, scanGeneration)
    if not playerInfo or not playerInfo.PlayerGuid then
        return false
    end

    if scanGeneration and playerInfo.ScanGeneration ~= scanGeneration then
        return false
    end

    return GearPolice:IsCurrentScan(playerInfo.PlayerGuid, scanGeneration)
end

function Inspection:IsStoredItemLink(slotValue)
    if not slotValue then
        return false
    end

    if slotValue == Constants.InventorySlotPending then
        return false
    end

    if slotValue == Constants.InventorySlotEmpty then
        return false
    end

    if slotValue == Constants.InventorySlotNoEvidence then
        return false
    end

    if slotValue == Constants.InventorySlotReady then
        return false
    end

    return true
end

function Inspection:IsItemMetadataPending(checkResult)
    return checkResult == Constants.ItemMetadataPending
end

function Inspection:RunProtectedCheck(callback)
    return xpcall(callback, function(errorMessage)
        local errorHandler = type(geterrorhandler) == "function" and geterrorhandler() or nil
        if type(errorHandler) == "function" then
            errorHandler(errorMessage)
        end

        return errorMessage
    end)
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

    return GearPolice.Problems.Add(playerInfo, {
        slotName = slotName,
        itemLink = itemLink,
        ruleId = ruleId,
        message = message,
    })
end
