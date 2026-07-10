local GearPolice = GearPolice

local UI = GearPolice.UI

UI.ViewModel = UI.ViewModel or {}

local ViewModel = UI.ViewModel

local StatusLabels = {
    InProgress = "|cffffcc00Scanning|r",
    Successful = "|cff40ff40Done|r",
    Partial = "|cffffcc00Partial|r",
    Failed = "|cffff4040Failed|r",
    TemporaryFailed = "|cffffcc00Retry|r",
    Cancelled = "|cffaaaaaaCancelled|r",
}

local function GetSlotLabel(slotName)
    return GearPolice.Slots.GetSlotLabel(slotName) or "Unknown Slot"
end

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
    problemLookup.problemCount = problemLookup.problemCount + 1
end

local function FormatIssueSummary(problemCount, hasPendingSlots)
    if problemCount > 0 then
        local suffix = problemCount == 1 and " issue" or " issues"
        return "|cffff4040" .. tostring(problemCount) .. suffix .. "|r"
    end

    if hasPendingSlots then
        return "|cffffcc00Pending|r"
    end

    return "|cffaaaaaaNo issues|r"
end

local function RowMatchesFilter(row, filterMode)
    if filterMode == "problems" then
        return row.hasProblems
    end

    if filterMode == "scanning" then
        return row.checkStatus == "InProgress"
    end

    if filterMode == "failed_partial" then
        return row.checkStatus == "Failed"
            or row.checkStatus == "Partial"
            or row.checkStatus == "TemporaryFailed"
    end

    return true
end

local function BuildSummary(rows)
    local issueCount = 0
    local scanningCount = 0

    for _, row in ipairs(rows) do
        issueCount = issueCount + (row.problemCount or 0)
        if row.checkStatus == "InProgress" then
            scanningCount = scanningCount + 1
        end
    end

    return {
        playerCount = #rows,
        issueCount = issueCount,
        scanningCount = scanningCount,
        text = "Players: "
            .. tostring(#rows)
            .. " | Issues: "
            .. tostring(issueCount)
            .. " | Scanning: "
            .. tostring(scanningCount),
    }
end

function ViewModel.BuildProblemLookup(playerInfo)
    local problemLookup = {
        bySlot = {},
        byItemLink = {},
        hasProblems = false,
        problemCount = 0,
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
            slotLabel = GetSlotLabel(slotName),
            state = "empty",
        }
    end

    if slotValue and slotValue ~= GearPolice.InventorySlotPending then
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(slotValue)
        local problems = problemLookup.bySlot[slotName] or problemLookup.byItemLink[slotValue] or {}

        return {
            slotName = slotName,
            slotLabel = GetSlotLabel(slotName),
            state = "item",
            itemLink = slotValue,
            texture = itemTexture or UI.QuestionMarkIcon,
            problems = problems,
            isProblematic = #problems > 0,
        }
    end

    return {
        slotName = slotName,
        slotLabel = GetSlotLabel(slotName),
        state = "pending",
        texture = UI.QuestionMarkIcon,
    }
end

function ViewModel.BuildRow(playerGuid, playerInfo, slotOrder)
    local slots = {}
    local problemLookup = ViewModel.BuildProblemLookup(playerInfo)
    local pendingSlotCount = 0

    for _, slotName in ipairs(slotOrder) do
        local slot = ViewModel.BuildSlot(playerInfo, slotName, problemLookup)
        if slot.state == "pending" then
            pendingSlotCount = pendingSlotCount + 1
        end

        table.insert(slots, slot)
    end

    local hasPendingSlots = pendingSlotCount > 0
        or playerInfo.CheckStatus == "InProgress"
        or playerInfo.CheckStatus == "Partial"
        or playerInfo.CheckStatus == "TemporaryFailed"

    return {
        playerGuid = playerGuid,
        playerInfo = playerInfo,
        playerName = playerInfo.PlayerName or "Unknown Player",
        checkStatus = playerInfo.CheckStatus,
        statusText = StatusLabels[playerInfo.CheckStatus] or (playerInfo.CheckStatus or "Unknown"),
        statusTexture = UI:GetCheckStatusTexture(playerInfo.CheckStatus),
        hasProblems = problemLookup.hasProblems,
        problemCount = problemLookup.problemCount,
        issueSummary = FormatIssueSummary(problemLookup.problemCount, hasPendingSlots),
        slots = slots,
    }
end

function ViewModel.BuildRows(filterMode)
    local rows = {}
    local slotOrder = GearPolice.Helper:GetInventorySlotNames()

    for _, playerGuid in ipairs(GearPolice:GetOrderedPlayerGuids()) do
        local playerInfo = GearPolice.db.global.PlayerGearInfo[playerGuid]
        if playerInfo then
            table.insert(rows, ViewModel.BuildRow(playerGuid, playerInfo, slotOrder))
        end
    end

    local summary = BuildSummary(rows)
    local filteredRows = {}

    for _, row in ipairs(rows) do
        if RowMatchesFilter(row, filterMode) then
            table.insert(filteredRows, row)
        end
    end

    return filteredRows, summary
end
