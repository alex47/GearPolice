local GearPolice = GearPolice

GearPolice.Reporting = GearPolice.Reporting or {}
local Reporting = GearPolice.Reporting
local ReportPrefix = "{Square} GearPolice {Cross}"

local function IsKnownPlayerName(playerName)
    return type(playerName) == "string" and playerName ~= "" and playerName ~= "Unknown"
end

local function GetWhisperRecipientForPlayer(playerInfo)
    if type(playerInfo) ~= "table" then
        return nil
    end

    if IsKnownPlayerName(playerInfo.PlayerFullName) then
        return playerInfo.PlayerFullName
    end

    if IsKnownPlayerName(playerInfo.PlayerName) then
        return playerInfo.PlayerName
    end

    return nil
end

local function AddReportableProblem(reportableItems, reportableItemsByKey, itemLink, slotName, message)
    if type(itemLink) ~= "string" or itemLink == "" or type(message) ~= "string" or message == "" then
        return
    end

    local key = tostring(slotName or "") .. "\001" .. itemLink
    local reportableItem = reportableItemsByKey[key]
    if not reportableItem then
        reportableItem = {
            itemLink = itemLink,
            slotName = slotName,
            problems = {},
        }
        reportableItemsByKey[key] = reportableItem
        table.insert(reportableItems, reportableItem)
    end

    table.insert(reportableItem.problems, message)
end

function Reporting:GetReportableProblematicItems(playerInfo)
    local reportableItems = {}
    local reportableItemsByKey = {}

    if type(playerInfo) ~= "table" then
        return reportableItems
    end

    if type(playerInfo.Problems) == "table" and #playerInfo.Problems > 0 then
        for _, problem in ipairs(playerInfo.Problems) do
            if type(problem) == "table" then
                AddReportableProblem(
                    reportableItems,
                    reportableItemsByKey,
                    problem.itemLink,
                    problem.slotName,
                    problem.message
                )
            end
        end

        return reportableItems
    end

    if type(playerInfo.ProblematicItems) ~= "table" then
        return reportableItems
    end

    for itemLink, problems in pairs(playerInfo.ProblematicItems) do
        if type(itemLink) == "string" then
            if type(problems) == "table" then
                for _, problem in ipairs(problems) do
                    AddReportableProblem(reportableItems, reportableItemsByKey, itemLink, nil, problem)
                end
            elseif type(problems) == "string" and problems ~= "" then
                AddReportableProblem(reportableItems, reportableItemsByKey, itemLink, nil, problems)
            end
        end
    end

    return reportableItems
end

function Reporting:GetReportableIssueCount(playerInfo)
    local issueCount = 0
    local reportableItems = self:GetReportableProblematicItems(playerInfo)

    for _, item in ipairs(reportableItems) do
        if type(item.problems) == "table" then
            issueCount = issueCount + #item.problems
        end
    end

    return issueCount
end

function Reporting:GetReportPrefix()
    return ReportPrefix
end

function Reporting:BuildProblemReportMessage(playerInfo, item, includePlayerName)
    local problemsStr = table.concat(item.problems, ", ")
    local playerPrefix = ""

    if includePlayerName then
        local playerName = type(playerInfo) == "table" and type(playerInfo.PlayerName) == "string"
            and playerInfo.PlayerName or nil
        playerPrefix = (playerName or "Unknown") .. " - "
    end

    return ReportPrefix .. " " .. playerPrefix .. item.itemLink .. ": " .. problemsStr
end

function Reporting:SendWhisper(recipientName, message, suppressLocal, priority)
    if type(recipientName) ~= "string" or recipientName == ""
        or type(message) ~= "string" or message == "" then
        return false
    end

    if suppressLocal and GearPolice.RegisterReportOfferOutgoingWhisper then
        GearPolice:RegisterReportOfferOutgoingWhisper(message)
    end

    return GearPolice.ChatThrottle:Send(message, "WHISPER", recipientName, priority or "NORMAL")
end

function Reporting:SendStatusWhisper(recipientName, statusMessage, suppressLocal, priority)
    if type(statusMessage) ~= "string" or statusMessage == "" then
        return false
    end

    return self:SendWhisper(recipientName, ReportPrefix .. " " .. statusMessage, suppressLocal, priority)
end

function Reporting:SendProblematicItemsWhisper(playerInfo, recipientName, suppressLocal, priority)
    local reportableItems = self:GetReportableProblematicItems(playerInfo)

    if #reportableItems == 0 then
        return false
    end

    for _, item in ipairs(reportableItems) do
        self:SendWhisper(recipientName, self:BuildProblemReportMessage(playerInfo, item), suppressLocal, priority)
    end

    return true
end

function Reporting:ReportProblematicItems_Print(playerInfo)
    local playerName = type(playerInfo) == "table" and type(playerInfo.PlayerName) == "string"
        and playerInfo.PlayerName or nil
    local reportableItems = self:GetReportableProblematicItems(playerInfo)

    if #reportableItems == 0 then
        return
    end

    GearPolice:Print("Player:", playerName or "Unknown")

    for _, item in ipairs(reportableItems) do
        local problemsStr = table.concat(item.problems, ", ")
        GearPolice:Print(item.itemLink .. ": " .. problemsStr)
    end
end

function Reporting:ReportProblematicItems(playerInfo)
    local whisperRecipient = GetWhisperRecipientForPlayer(playerInfo)
    local reportableItems = self:GetReportableProblematicItems(playerInfo)

    if #reportableItems == 0 then
        return
    end

    for _, item in ipairs(reportableItems) do
        local reportMode = GearPolice.db.global.ReportMode
        local message = self:BuildProblemReportMessage(playerInfo, item, reportMode == "public")

        if reportMode == "public" then
            GearPolice.ChatThrottle:Send(message, IsInRaid() and "RAID" or "PARTY", nil, "NORMAL")
        elseif reportMode == "debug" then
            GearPolice:Print(message)
        elseif whisperRecipient then
            GearPolice.ChatThrottle:Send(message, "WHISPER", whisperRecipient, "NORMAL")
        end
    end
end
