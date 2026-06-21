local GearPolice = GearPolice

local UI = GearPolice.UI

UI.ViewModel = UI.ViewModel or {}

local ViewModel = UI.ViewModel

local function AddProblem(problemLookup, slotName, itemLink, ruleId, message)
    if type(message) ~= "string" or message == "" then
        return
    end

    local problem = {
        slotName = slotName,
        itemLink = itemLink,
        ruleId = ruleId,
        message = message,
    }

    if slotName then
        problemLookup.bySlot[slotName] = problemLookup.bySlot[slotName] or {}
        table.insert(problemLookup.bySlot[slotName], problem)
    end

    if type(itemLink) == "string" then
        problemLookup.byItemLink[itemLink] = problemLookup.byItemLink[itemLink] or {}
        table.insert(problemLookup.byItemLink[itemLink], problem)
    end

    problemLookup.hasProblems = true
end

function ViewModel.BuildProblemLookup(playerInfo)
    local problemLookup = {
        bySlot = {},
        byItemLink = {},
        hasProblems = false,
    }

    if type(playerInfo.Problems) == "table" and #playerInfo.Problems > 0 then
        for _, problem in ipairs(playerInfo.Problems) do
            if type(problem) == "table" then
                AddProblem(
                    problemLookup,
                    problem.slotName,
                    problem.itemLink,
                    problem.ruleId,
                    problem.message
                )
            end
        end

        return problemLookup
    end

    if type(playerInfo.ProblematicItems) == "table" then
        for itemLink, problems in pairs(playerInfo.ProblematicItems) do
            if type(problems) == "table" then
                for _, message in ipairs(problems) do
                    AddProblem(problemLookup, nil, itemLink, nil, message)
                end
            elseif type(problems) == "string" then
                AddProblem(problemLookup, nil, itemLink, nil, problems)
            end
        end
    end

    return problemLookup
end

function ViewModel.BuildSlot(playerInfo, slotName, problemLookup)
    local slotValue = playerInfo.EquippedItems and playerInfo.EquippedItems[slotName]

    if slotValue == GearPolice.InventorySlotEmpty then
        return {
            slotName = slotName,
            state = "empty",
        }
    end

    if slotValue and slotValue ~= GearPolice.InventorySlotPending then
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(slotValue)
        local problems = problemLookup.bySlot[slotName] or problemLookup.byItemLink[slotValue] or {}

        return {
            slotName = slotName,
            state = "item",
            itemLink = slotValue,
            texture = itemTexture or UI.QuestionMarkIcon,
            problems = problems,
            isProblematic = #problems > 0,
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
    local problemLookup = ViewModel.BuildProblemLookup(playerInfo)

    for _, slotName in ipairs(slotOrder) do
        table.insert(slots, ViewModel.BuildSlot(playerInfo, slotName, problemLookup))
    end

    return {
        playerGuid = playerGuid,
        playerInfo = playerInfo,
        playerName = playerInfo.PlayerName or "Unknown Player",
        checkStatus = playerInfo.CheckStatus,
        statusTexture = UI:GetCheckStatusTexture(playerInfo.CheckStatus),
        hasProblems = problemLookup.hasProblems,
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
