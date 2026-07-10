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

local function GetPlayerPrefix(playerInfo, includePlayerName)
    if not includePlayerName then
        return ""
    end

    local playerName = type(playerInfo) == "table" and type(playerInfo.PlayerName) == "string"
        and playerInfo.PlayerName or nil
    return (playerName or "Unknown") .. " - "
end

local function GetSlotLabel(slotName)
    return GearPolice.Slots.GetSlotLabel(slotName)
end

local function GetItemNameFromLink(itemLink)
    if type(itemLink) ~= "string" then
        return "Item"
    end

    local itemName = GetItemInfo(itemLink)
    if IsKnownPlayerName(itemName) then
        return itemName
    end

    return itemLink:match("%[(.-)%]") or "Item"
end

local function BuildFallbackItemReference(item)
    local itemName = GetItemNameFromLink(item.itemLink)
    local slotLabel = GetSlotLabel(item.slotName)

    if slotLabel then
        return slotLabel .. " - " .. itemName
    end

    return itemName
end

local function RegisterOutgoingWhisperSuppression(message)
    if not GearPolice.RegisterReportOfferOutgoingWhisper then
        return
    end

    if GearPolice.ChatThrottle and GearPolice.ChatThrottle.GetMessageChunks then
        for _, messageChunk in ipairs(GearPolice.ChatThrottle:GetMessageChunks(message)) do
            GearPolice:RegisterReportOfferOutgoingWhisper(messageChunk)
        end
        return
    end

    GearPolice:RegisterReportOfferOutgoingWhisper(message)
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

function Reporting:BuildProblemReportMessages(playerInfo, item, includePlayerName)
    local problemsStr = table.concat(item.problems, ", ")
    local playerPrefix = GetPlayerPrefix(playerInfo, includePlayerName)
    local messagePrefix = ReportPrefix .. " " .. playerPrefix
    local fullMessage = messagePrefix .. item.itemLink .. ": " .. problemsStr

    local maxMessageLength = GearPolice.ChatThrottle:GetMaxMessageLength()
    if #fullMessage <= maxMessageLength then
        return { fullMessage }
    end

    if #(messagePrefix .. item.itemLink) <= maxMessageLength then
        return {
            messagePrefix .. item.itemLink,
            messagePrefix .. "Issues: " .. problemsStr,
        }
    end

    if #item.itemLink <= maxMessageLength then
        return {
            messagePrefix .. "Item:",
            item.itemLink,
            messagePrefix .. "Issues: " .. problemsStr,
        }
    end

    return {
        messagePrefix .. BuildFallbackItemReference(item),
        messagePrefix .. "Issues: " .. problemsStr,
    }
end

function Reporting:BuildProblemReportMessage(playerInfo, item, includePlayerName)
    return table.concat(self:BuildProblemReportMessages(playerInfo, item, includePlayerName), " ")
end

function Reporting:SendWhisper(recipientName, message, suppressLocal, priority)
    if type(recipientName) ~= "string" or recipientName == ""
        or type(message) ~= "string" or message == "" then
        return false
    end

    if suppressLocal and GearPolice.RegisterReportOfferOutgoingWhisper then
        RegisterOutgoingWhisperSuppression(message)
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
        for _, message in ipairs(self:BuildProblemReportMessages(playerInfo, item)) do
            self:SendWhisper(recipientName, message, suppressLocal, priority)
        end
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
        for _, message in ipairs(self:BuildProblemReportMessages(playerInfo, item)) do
            GearPolice:Print(message)
        end
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
        local messages = self:BuildProblemReportMessages(playerInfo, item, reportMode == "public")

        for _, message in ipairs(messages) do
            if reportMode == "public" then
                GearPolice.ChatThrottle:Send(message, IsInRaid() and "RAID" or "PARTY", nil, "NORMAL")
            elseif reportMode == "debug" then
                GearPolice:Print(message)
            elseif whisperRecipient then
                GearPolice.ChatThrottle:Send(message, "WHISPER", whisperRecipient, "NORMAL")
            end
        end
    end
end
