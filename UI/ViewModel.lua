local GearPolice = GearPolice

local UI = GearPolice.UI

UI.ViewModel = UI.ViewModel or {}

local ViewModel = UI.ViewModel
local Constants = GearPolice.Constants
local ScanStatus = GearPolice.Constants.ScanStatus
local PlayerListFilter = GearPolice.Settings.PlayerListFilter

local StatusLabels = {
    [ScanStatus.NotScanned] = "|cffaaaaaaNot Scanned|r",
    [ScanStatus.InProgress] = "|cffffcc00Scanning|r",
    [ScanStatus.Successful] = "|cff40ff40Done|r",
    [ScanStatus.Partial] = "|cffffcc00Partial|r",
    [ScanStatus.Failed] = "|cffff4040Failed|r",
    [ScanStatus.TemporaryFailed] = "|cffffcc00Retry|r",
    [ScanStatus.Cancelled] = "|cffaaaaaaCancelled|r",
}

local function GetSlotLabel(slotName)
    return GearPolice.Slots.GetSlotLabel(slotName) or "Unknown Slot"
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

local function NormalizePlayerSortName(playerName)
    return GearPolice.Players.NormalizeShortName(playerName)
end

local function PlayerRowComesBefore(rowA, rowB)
    local nameA = NormalizePlayerSortName(rowA.playerName)
    local nameB = NormalizePlayerSortName(rowB.playerName)

    if (nameA ~= nil) ~= (nameB ~= nil) then
        return nameA ~= nil
    end

    if nameA ~= nameB then
        return (nameA or "") < (nameB or "")
    end

    local fullNameA = GearPolice.Players.NormalizeFullName(
        rowA.playerInfo and rowA.playerInfo.PlayerFullName
    ) or nameA
    local fullNameB = GearPolice.Players.NormalizeFullName(
        rowB.playerInfo and rowB.playerInfo.PlayerFullName
    ) or nameB
    if fullNameA ~= fullNameB then
        return (fullNameA or "") < (fullNameB or "")
    end

    return tostring(rowA.playerGuid or "") < tostring(rowB.playerGuid or "")
end

local function RowMatchesFilter(row, filterMode)
    if filterMode == PlayerListFilter.Problems then
        return row.hasProblems
    end

    if filterMode == PlayerListFilter.Scanning then
        return row.checkStatus == ScanStatus.InProgress
    end

    if filterMode == PlayerListFilter.FailedPartial then
        return row.checkStatus == ScanStatus.Failed
            or row.checkStatus == ScanStatus.Partial
            or row.checkStatus == ScanStatus.TemporaryFailed
    end

    return true
end

local function BuildSummary(rows)
    local issueCount = 0
    local scanningCount = 0

    for _, row in ipairs(rows) do
        issueCount = issueCount + (row.problemCount or 0)
        if row.checkStatus == ScanStatus.InProgress then
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
    return GearPolice.Problems.BuildIndex(playerInfo)
end

function ViewModel.BuildSlot(playerInfo, slotName, problemLookup)
    local slotValue = playerInfo.EquippedItems and playerInfo.EquippedItems[slotName]

    if playerInfo.CheckStatus == ScanStatus.NotScanned and not slotValue then
        return {
            slotName = slotName,
            slotLabel = GetSlotLabel(slotName),
            state = "not_scanned",
            texture = UI.QuestionMarkIcon,
        }
    end

    if slotValue == Constants.InventorySlotEmpty then
        return {
            slotName = slotName,
            slotLabel = GetSlotLabel(slotName),
            state = "empty",
        }
    end

    if slotValue and slotValue ~= Constants.InventorySlotPending then
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(slotValue)
        local problems = problemLookup.bySlot[slotName]
        if not problems or #problems == 0 then
            problems = problemLookup.unownedByItemLink[slotValue] or {}
        end

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

    for _, slotName in ipairs(slotOrder) do
        local slot = ViewModel.BuildSlot(playerInfo, slotName, problemLookup)
        table.insert(slots, slot)
    end

    local hasPendingSlots = playerInfo.CheckStatus == ScanStatus.InProgress
        or playerInfo.CheckStatus == ScanStatus.Partial
        or playerInfo.CheckStatus == ScanStatus.TemporaryFailed

    local issueSummary
    if playerInfo.CheckStatus == ScanStatus.NotScanned then
        issueSummary = "|cffaaaaaaNot scanned|r"
    else
        issueSummary = FormatIssueSummary(problemLookup.totalProblemCount, hasPendingSlots)
    end

    return {
        playerGuid = playerGuid,
        playerInfo = playerInfo,
        playerName = playerInfo.PlayerName or "Unknown Player",
        checkStatus = playerInfo.CheckStatus,
        statusText = StatusLabels[playerInfo.CheckStatus] or (playerInfo.CheckStatus or "Unknown"),
        statusTexture = UI:GetCheckStatusTexture(playerInfo.CheckStatus),
        hasProblems = problemLookup.hasProblems,
        problemCount = problemLookup.totalProblemCount,
        issueSummary = issueSummary,
        slots = slots,
    }
end

function ViewModel.BuildRows(filterMode)
    local rows = {}
    local slotOrder = GearPolice.Slots.GetInventorySlotNames()
    local playerGearInfo = GearPolice.PlayerStore:GetAll()

    for playerGuid, playerInfo in pairs(playerGearInfo or {}) do
        table.insert(rows, ViewModel.BuildRow(playerGuid, playerInfo, slotOrder))
    end

    table.sort(rows, PlayerRowComesBefore)

    local summary = BuildSummary(rows)
    local filteredRows = {}

    for _, row in ipairs(rows) do
        if RowMatchesFilter(row, filterMode) then
            table.insert(filteredRows, row)
        end
    end

    return filteredRows, summary
end
