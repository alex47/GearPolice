local GearPolice = GearPolice

GearPolice.Units = GearPolice.Units or {}
GearPolice.Helper = GearPolice.Helper or {}

local Units = GearPolice.Units
local Helper = GearPolice.Helper

function Units.GetUnitIdOfPlayerGuid(playerGuid)
    if UnitGUID("player") == playerGuid then
        return "player"
    end

    if UnitGUID("target") == playerGuid then
        return "target"
    end

    local roster = GearPolice.currentRoster
    if roster and roster.unitIdByGuid then
        local unitId = roster.unitIdByGuid[playerGuid]
        if unitId and UnitGUID(unitId) == playerGuid then
            return unitId
        end
    end

    if IsInRaid() then
        for i = 1, 40 do
            local unitId = "raid" .. i
            local playerGuid2 = UnitGUID(unitId)

            if playerGuid == playerGuid2 then
                return unitId
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local unitId = "party" .. i
            local playerGuid2 = UnitGUID(unitId)

            if playerGuid == playerGuid2 then
                return unitId
            end
        end
    end

    return nil
end

function Units.IsPlayerInGroup(playerGuid)
    if IsInRaid() then
        for i = 1, 40 do
            local unitId = "raid" .. i
            if UnitExists(unitId) and UnitGUID(unitId) == playerGuid then
                return true
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local unitId = "party" .. i
            if UnitExists(unitId) and UnitGUID(unitId) == playerGuid then
                return true
            end
        end
    end

    return UnitGUID("player") == playerGuid
end

function Helper:GetUnitIdOfPlayerGuid(playerGuid)
    return Units.GetUnitIdOfPlayerGuid(playerGuid)
end

function Helper:IsPlayerInGroup(playerGuid)
    return Units.IsPlayerInGroup(playerGuid)
end
