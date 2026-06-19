local GearPolice = GearPolice

GearPolice.Reporting = GearPolice.Reporting or {}
local Reporting = GearPolice.Reporting



function Reporting:ReportProblematicItems_Print(playerInfo)
    GearPolice:Print("Player:", playerInfo.PlayerName)

    for itemLink, problems in pairs(playerInfo.ProblematicItems) do
        local problemsStr = table.concat(problems, ", ")
        GearPolice:Print(itemLink .. ": " .. problemsStr)
    end
end

function Reporting:ReportProblematicItems(playerInfo)
    for itemLink, problems in pairs(playerInfo.ProblematicItems) do
        local problemsStr = table.concat(problems, ", ")
        local message = "{Square} GearPolice {Cross} " .. playerInfo.PlayerName .. " - " .. itemLink .. ": " .. problemsStr
        local reportMode = GearPolice.db.global.ReportMode

        if reportMode == "public" then
            SendChatMessage(message, IsInRaid() and "RAID" or "PARTY")
        elseif reportMode == "debug" then
            GearPolice:Print(message)
        else
            SendChatMessage(message, "WHISPER", nil, playerInfo.PlayerName)
        end
    end
end
