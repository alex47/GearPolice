local GearPolice = GearPolice

GearPolice.Helper = GearPolice.Helper or {}
local Helper = GearPolice.Helper



function Helper:GetUnitIdOfPlayerGuid(playerGuid)
    if UnitGUID("target") == playerGuid then
        return "target"
    elseif IsInRaid() then
        for i = 1, 40 do
            local unitId = "raid" .. i
            local playerGuid2 = UnitGUID(unitId)

            if (playerGuid == playerGuid2) then
                return unitId
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local unitId = "party" .. i
            local playerGuid2 = UnitGUID(unitId)

            if (playerGuid == playerGuid2) then
                return unitId
            end
        end
    end

    return nil
end

function Helper:tContains(table, value)
    for _, v in pairs(table) do
        if v == value then return true end
    end
    return false
end

function Helper:IsPlayerInGroup(playerGuid)
    -- Check raid
    if IsInRaid() then
        for i = 1, 40 do
            local unitId = "raid" .. i
            if UnitExists(unitId) and UnitGUID(unitId) == playerGuid then
                return true
            end
        end
    -- Check party
    elseif IsInGroup() then
        for i = 1, 4 do
            local unitId = "party" .. i
            if UnitExists(unitId) and UnitGUID(unitId) == playerGuid then
                return true
            end
        end
    end

    -- Check player themselves
    return UnitGUID("player") == playerGuid
end