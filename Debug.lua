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
    local playerInfo = self.db.global.PlayerGearInfo[playerGuid]
    local playerName = playerInfo["PlayerName"]

    if (0 < #playerInfo["ItemLinksMissingGems"] or 0 < #playerInfo["ItemLinksMissingEnchants"]) then
        GearPolice:Print("-------------------------")
        GearPolice:Print(playerName)

        -- Printing the contents of the ItemLinksMissingGems list
        if 0 < #playerInfo["ItemLinksMissingGems"] then
            GearPolice:Print("Gems Missing In:")
            for _, itemLink in ipairs(playerInfo["ItemLinksMissingGems"]) do
                GearPolice:Print(itemLink)
            end
        end

        -- Printing the contents of the ItemLinksMissingEnchants list
        if 0 < #playerInfo["ItemLinksMissingEnchants"] then
            GearPolice:Print("Enchants Missing In:")
            for _, itemLink in ipairs(playerInfo["ItemLinksMissingEnchants"]) do
                GearPolice:Print(itemLink)
            end
        end
    end
end
