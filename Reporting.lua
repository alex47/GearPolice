local GearPolice = GearPolice

GearPolice.Reporting = GearPolice.Reporting or {}
local Reporting = GearPolice.Reporting
local ReportPrefix = "{Square} " .. GearPolice.AddonName .. " {Cross}"

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
    if GearPolice.Players.IsKnownName(itemName) then
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

local function RegisterOutgoingWhisperSuppression(recipientName, message)
    if not GearPolice.RegisterReportOfferOutgoingWhisper then
        return
    end

    if GearPolice.ChatThrottle and GearPolice.ChatThrottle.GetMessageChunks then
        for _, messageChunk in ipairs(GearPolice.ChatThrottle:GetMessageChunks(message)) do
            GearPolice:RegisterReportOfferOutgoingWhisper(recipientName, messageChunk)
        end
        return
    end

    GearPolice:RegisterReportOfferOutgoingWhisper(recipientName, message)
end

local function RenderIssueSummaryLine(line)
    local message
    if line.text then
        message = line.text
    else
        message = line.prefix .. table.concat(line.segments, ", ") .. "."
    end

    if line.finalText then
        message = message .. " " .. line.finalText
    end

    return message
end

local function BuildIssueSummaryMessages(breakdown, options)
    local maxMessageLength = GearPolice.ChatThrottle:GetMaxMessageLength()
    local lines = {}

    if #breakdown == 0 then
        table.insert(lines, {
            text = options.fallbackMessage,
        })
    else
        local currentLine = {
            prefix = options.summaryPrefix,
            segments = {},
        }

        local function FinishCurrentLine()
            if #currentLine.segments == 0 then
                return
            end

            table.insert(lines, currentLine)
            currentLine = {
                prefix = options.continuationPrefix,
                segments = {},
            }
        end

        for _, issue in ipairs(breakdown) do
            local segment = tostring(issue.count) .. "x " .. issue.label
            if #(options.continuationPrefix .. segment .. ".") > maxMessageLength then
                segment = tostring(issue.count) .. "x Other Issue"
            end

            local candidateSegments = {}
            for _, currentSegment in ipairs(currentLine.segments) do
                table.insert(candidateSegments, currentSegment)
            end
            table.insert(candidateSegments, segment)

            local candidate = currentLine.prefix .. table.concat(candidateSegments, ", ") .. "."
            if #candidate > maxMessageLength then
                if #currentLine.segments > 0 then
                    FinishCurrentLine()
                elseif #lines == 0 then
                    table.insert(lines, {
                        text = options.fallbackMessage,
                    })
                    currentLine.prefix = options.continuationPrefix
                end
            end

            table.insert(currentLine.segments, segment)
        end

        FinishCurrentLine()
    end

    if options.finalText then
        local lastLine = lines[#lines]
        local messageWithFinalText = RenderIssueSummaryLine(lastLine) .. " " .. options.finalText

        if #messageWithFinalText <= maxMessageLength then
            lastLine.finalText = options.finalText
        elseif lastLine.segments and #lastLine.segments > 0 then
            local lastSegment = lastLine.segments[#lastLine.segments]
            local finalLine = {
                prefix = options.continuationPrefix,
                segments = { lastSegment },
                finalText = options.finalText,
            }

            if #RenderIssueSummaryLine(finalLine) <= maxMessageLength then
                table.remove(lastLine.segments)
                if #lastLine.segments == 0 then
                    if #lines == 1 then
                        lines[1] = {
                            text = options.fallbackMessage,
                        }
                    else
                        table.remove(lines)
                    end
                end
                table.insert(lines, finalLine)
            else
                table.insert(lines, {
                    text = options.finalMessagePrefix .. options.finalText,
                })
            end
        else
            table.insert(lines, {
                text = options.finalMessagePrefix .. options.finalText,
            })
        end
    end

    local messages = {}
    for _, line in ipairs(lines) do
        table.insert(messages, RenderIssueSummaryLine(line))
    end
    return messages
end

function Reporting:GetReportableProblematicItems(playerInfo)
    if type(playerInfo) ~= "table" then
        return {}
    end

    return GearPolice.Problems.BuildIndex(playerInfo).reportableItems
end

function Reporting:GetReportableIssueBreakdown(playerInfo)
    local countsByRuleId = {}
    local unknownCountsByLabel = {}
    local issueCount = 0
    local reportableItems = self:GetReportableProblematicItems(playerInfo)

    for _, item in ipairs(reportableItems) do
        for _, problem in ipairs(item.problemRecords or {}) do
            issueCount = issueCount + 1

            local summaryLabel = GearPolice.Rules.GetIssueSummaryLabel(problem.ruleId)
            if summaryLabel then
                countsByRuleId[problem.ruleId] = (countsByRuleId[problem.ruleId] or 0) + 1
            else
                local label = type(problem.message) == "string" and problem.message or "Other Issue"
                unknownCountsByLabel[label] = (unknownCountsByLabel[label] or 0) + 1
            end
        end
    end

    local breakdown = {}
    for _, ruleId in ipairs(GearPolice.Rules.GetIssueSummaryRuleIds()) do
        local count = countsByRuleId[ruleId]
        if count then
            table.insert(breakdown, {
                ruleId = ruleId,
                label = GearPolice.Rules.GetIssueSummaryLabel(ruleId),
                count = count,
            })
        end
    end

    local unknownLabels = {}
    for label in pairs(unknownCountsByLabel) do
        table.insert(unknownLabels, label)
    end
    table.sort(unknownLabels, function(left, right)
        local normalizedLeft = string.lower(left)
        local normalizedRight = string.lower(right)
        if normalizedLeft == normalizedRight then
            return left < right
        end

        return normalizedLeft < normalizedRight
    end)

    for _, label in ipairs(unknownLabels) do
        table.insert(breakdown, {
            label = label,
            count = unknownCountsByLabel[label],
        })
    end

    return breakdown, issueCount
end

function Reporting:GetReportableIssueCount(playerInfo)
    local _, issueCount = self:GetReportableIssueBreakdown(playerInfo)
    return issueCount
end

function Reporting:GetReportPrefix()
    return ReportPrefix
end

function Reporting:BuildPublicScanSummaryMessages(playerInfo)
    if type(playerInfo) ~= "table" or not GearPolice.Players.IsKnownName(playerInfo.PlayerName) then
        return {}
    end

    local breakdown, issueCount = self:GetReportableIssueBreakdown(playerInfo)
    if issueCount <= 0 then
        return {}
    end

    local issueWord = issueCount == 1 and "issue" or "issues"
    local playerPrefix = self:GetReportPrefix() .. " " .. playerInfo.PlayerName .. " - "
    local summaryText = tostring(issueCount) .. " gear " .. issueWord .. " found"
    return BuildIssueSummaryMessages(breakdown, {
        summaryPrefix = playerPrefix .. summaryText .. ": ",
        continuationPrefix = playerPrefix .. "Continued: ",
        fallbackMessage = playerPrefix .. summaryText .. ".",
    })
end

function Reporting:BuildReportOfferMessages(playerInfo)
    local breakdown, issueCount = self:GetReportableIssueBreakdown(playerInfo)
    if issueCount <= 0 then
        return {}
    end

    local issueWord = issueCount == 1 and "issue" or "issues"
    local verb = issueCount == 1 and "was" or "were"
    local summaryText = tostring(issueCount) .. " " .. issueWord
        .. " " .. verb .. " found in your equipped gear"

    return BuildIssueSummaryMessages(breakdown, {
        summaryPrefix = ReportPrefix .. " " .. summaryText .. ": ",
        continuationPrefix = ReportPrefix .. " Continued: ",
        fallbackMessage = ReportPrefix .. " " .. summaryText .. ".",
        finalText = "Whisper me \"!gp\" to get the full report.",
        finalMessagePrefix = ReportPrefix .. " ",
    })
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

function Reporting:BuildPlayerReportMessages(playerInfo, includePlayerName)
    local messages = {}

    for _, item in ipairs(self:GetReportableProblematicItems(playerInfo)) do
        for _, message in ipairs(self:BuildProblemReportMessages(playerInfo, item, includePlayerName)) do
            table.insert(messages, message)
        end
    end

    return messages
end

function Reporting:SendWhisper(recipientName, message, suppressLocal, priority)
    if type(recipientName) ~= "string" or recipientName == ""
        or type(message) ~= "string" or message == "" then
        return false
    end

    if suppressLocal and GearPolice.RegisterReportOfferOutgoingWhisper then
        RegisterOutgoingWhisperSuppression(recipientName, message)
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
    local messages = self:BuildPlayerReportMessages(playerInfo, false)
    if #messages == 0 then
        return false
    end

    for _, message in ipairs(messages) do
        if not self:SendWhisper(recipientName, message, suppressLocal, priority) then
            return false
        end
    end

    return true
end

function Reporting:ReportProblematicItems_Print(playerInfo)
    local playerName = type(playerInfo) == "table" and type(playerInfo.PlayerName) == "string"
        and playerInfo.PlayerName or nil
    local messages = self:BuildPlayerReportMessages(playerInfo, false)
    if #messages == 0 then
        return false
    end

    GearPolice:Print("Player:", playerName or "Unknown")
    for _, message in ipairs(messages) do
        GearPolice:Print(message)
    end
    return true
end

function Reporting:ReportProblematicItems(playerInfo)
    local reportMode = GearPolice.Settings:GetReportMode()
    local ReportMode = GearPolice.Settings.ReportMode
    local messages = self:BuildPlayerReportMessages(playerInfo, reportMode == ReportMode.Public)
    if #messages == 0 then
        return false
    end

    local whisperRecipient = GearPolice.Players.GetWhisperRecipient(playerInfo)
    local groupChatType = GearPolice.Units.GetGroupChatType()
    for _, message in ipairs(messages) do
        local sent
        if reportMode == ReportMode.Public then
            sent = groupChatType
                and GearPolice.ChatThrottle:Send(message, groupChatType, nil, "NORMAL")
        elseif reportMode == ReportMode.Debug then
            GearPolice:Print(message)
            sent = true
        elseif whisperRecipient then
            sent = self:SendWhisper(whisperRecipient, message, false, "NORMAL")
        end

        if not sent then
            return false
        end
    end

    return true
end
