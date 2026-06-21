local GearPolice = GearPolice

GearPolice.Reporting = GearPolice.Reporting or {}
local Reporting = GearPolice.Reporting


function Reporting:GetReportableProblematicItems(playerInfo)
    local reportableItems = {}

    if type(playerInfo) ~= "table" or type(playerInfo.ProblematicItems) ~= "table" then
        return reportableItems
    end

    for itemLink, problems in pairs(playerInfo.ProblematicItems) do
        if type(itemLink) == "string" then
            local reportableProblems = {}

            if type(problems) == "table" then
                for _, problem in ipairs(problems) do
                    if type(problem) == "string" and problem ~= "" then
                        table.insert(reportableProblems, problem)
                    end
                end
            elseif type(problems) == "string" and problems ~= "" then
                table.insert(reportableProblems, problems)
            end

            if #reportableProblems > 0 then
                table.insert(reportableItems, {
                    itemLink = itemLink,
                    problems = reportableProblems,
                })
            end
        end
    end

    return reportableItems
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
    local playerName = type(playerInfo) == "table" and type(playerInfo.PlayerName) == "string"
        and playerInfo.PlayerName or nil
    local reportableItems = self:GetReportableProblematicItems(playerInfo)

    if #reportableItems == 0 then
        return
    end

    for _, item in ipairs(reportableItems) do
        local problemsStr = table.concat(item.problems, ", ")
        local message = "{Square} GearPolice {Cross} " .. (playerName or "Unknown") .. " - "
            .. item.itemLink .. ": " .. problemsStr
        local reportMode = GearPolice.db.global.ReportMode

        if reportMode == "public" then
            SendChatMessage(message, IsInRaid() and "RAID" or "PARTY")
        elseif reportMode == "debug" then
            GearPolice:Print(message)
        elseif playerName and playerName ~= "" and playerName ~= "Unknown" then
            SendChatMessage(message, "WHISPER", nil, playerName)
        end
    end
end
