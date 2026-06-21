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
    local reportableItems = GearPolice.Reporting:GetReportableProblematicItems(playerInfo)

    if #reportableItems == 0 then
        GearPolice:Print(playerName .. ": no gear issues recorded.")
        return
    end

    GearPolice:Print("-------------------------")
    GearPolice:Print(playerName)

    for _, item in ipairs(reportableItems) do
        local issues = table.concat(item.problems, ", ")
        if item.slotName then
            GearPolice:Print(item.slotName .. " " .. item.itemLink .. " => " .. issues)
        else
            GearPolice:Print(item.itemLink .. " => " .. issues)
        end
    end
end
