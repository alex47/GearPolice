local GearPolice = GearPolice

local UI = GearPolice.UI

UI.ViewModel = UI.ViewModel or {}

local ViewModel = UI.ViewModel

function ViewModel.BuildSlot(playerInfo, slotName)
    local slotValue = playerInfo.EquippedItems and playerInfo.EquippedItems[slotName]

    if slotValue == GearPolice.InventorySlotEmpty then
        return {
            slotName = slotName,
            state = "empty",
        }
    end

    if slotValue and slotValue ~= GearPolice.InventorySlotPending then
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(slotValue)
        return {
            slotName = slotName,
            state = "item",
            itemLink = slotValue,
            texture = itemTexture or UI.QuestionMarkIcon,
            isProblematic = playerInfo.ProblematicItems and playerInfo.ProblematicItems[slotValue],
        }
    end

    return {
        slotName = slotName,
        state = "pending",
        texture = UI.QuestionMarkIcon,
    }
end

function ViewModel.BuildRow(playerGuid, playerInfo, slotOrder)
    local slots = {}
    for _, slotName in ipairs(slotOrder) do
        table.insert(slots, ViewModel.BuildSlot(playerInfo, slotName))
    end

    return {
        playerGuid = playerGuid,
        playerInfo = playerInfo,
        playerName = playerInfo.PlayerName or "Unknown Player",
        checkStatus = playerInfo.CheckStatus,
        statusTexture = UI:GetCheckStatusTexture(playerInfo.CheckStatus),
        hasProblems = playerInfo.ProblematicItems and next(playerInfo.ProblematicItems) ~= nil,
        slots = slots,
    }
end

function ViewModel.BuildRows()
    local rows = {}
    local slotOrder = GearPolice.Helper:GetInventorySlotNames()

    for _, playerGuid in ipairs(GearPolice:GetOrderedPlayerGuids()) do
        local playerInfo = GearPolice.db.global.PlayerGearInfo[playerGuid]
        if playerInfo then
            table.insert(rows, ViewModel.BuildRow(playerGuid, playerInfo, slotOrder))
        end
    end

    return rows
end
