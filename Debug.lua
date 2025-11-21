local GearPolice = GearPolice

GearPolice.Debug = GearPolice.Debug or {}
local Debug = GearPolice.Debug



function Debug:PrintTable(t, indent)
    indent = indent or ""
    for key, value in pairs(t) do
        if type(value) == "table" then
            GearPolice:Print(indent .. tostring(key) .. ":")
            Debug:PrintTable(value, indent .. "  ")
        else
            GearPolice:Print(indent .. tostring(key) .. ": " .. tostring(value))
        end
    end
end

function Debug:Message(message)
    if GearPolice.db.global.DebugEnabled then
        GearPolice:Print(message)
    end
end

function Debug:PrintInspectionSummary(playerGuid)
    if not GearPolice.db or not GearPolice.db.global or not GearPolice.db.global.PlayerGearInfo then
        GearPolice:Print("GearPolice DB not initialized.")
        return
    end

    local playerInfo = GearPolice.db.global.PlayerGearInfo[playerGuid]
    if not playerInfo then
        GearPolice:Print("No inspection data for player GUID: " .. tostring(playerGuid))
        return
    end

    local playerName = playerInfo.PlayerName or "Unknown Player"
    local problems = playerInfo.ProblematicItems

    if not problems or not next(problems) then
        GearPolice:Print(playerName .. ": no gear issues recorded.")
        return
    end

    GearPolice:Print("-------------------------")
    GearPolice:Print(playerName)

    for itemLink, issueList in pairs(problems) do
        local issues = table.concat(issueList, ", ")
        GearPolice:Print(itemLink .. " => " .. issues)
    end
end
