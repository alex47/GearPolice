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

        if GearPolice.db.global.PublicShamingEnabled then
            -- Send to RAID or PARTY chat
            SendChatMessage(message, IsInRaid() and "RAID" or "PARTY")
        else
            -- Whisper to the player
            SendChatMessage(message, "WHISPER", nil, playerInfo.PlayerName)
        end
    end
end
