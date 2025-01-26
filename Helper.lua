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