local GearPolice = GearPolice

GearPolice.Players = GearPolice.Players or {}

local Players = GearPolice.Players

function Players.IsKnownName(name)
    return type(name) == "string"
        and name ~= ""
        and name ~= "Unknown"
        and name ~= "Unknown Player"
end

function Players.IsPlayerGuid(value)
    return type(value) == "string" and string.find(value, "^Player%-") ~= nil
end

function Players.BuildFullName(name, realm)
    if not Players.IsKnownName(name) then
        return nil
    end

    if type(realm) == "string" and realm ~= "" then
        return name .. "-" .. realm
    end

    return name
end

function Players.GetUnitFullName(unitId)
    if type(unitId) ~= "string" or not UnitExists(unitId) then
        return nil
    end

    local name, realm = UnitName(unitId)
    if unitId == "player" and (not realm or realm == "") and type(GetRealmName) == "function" then
        realm = GetRealmName()
    end

    return Players.BuildFullName(name, realm)
end

function Players.NormalizeFullName(name)
    if not Players.IsKnownName(name) then
        return nil
    end

    return string.lower(name)
end

function Players.NormalizeShortName(name)
    if not Players.IsKnownName(name) then
        return nil
    end

    return string.lower(name:match("^([^%-]+)") or name)
end

function Players.GetStoredFullName(playerInfo)
    if type(playerInfo) ~= "table" then
        return nil
    end

    if Players.IsKnownName(playerInfo.PlayerFullName) then
        return playerInfo.PlayerFullName
    end

    if Players.IsKnownName(playerInfo.PlayerName) then
        return playerInfo.PlayerName
    end

    return nil
end

function Players.GetWhisperRecipient(playerInfo)
    if type(playerInfo) ~= "table" then
        return nil
    end

    local unitId = playerInfo.CurrentUnitId
    if type(unitId) == "string" and UnitGUID(unitId) == playerInfo.PlayerGuid then
        local unitFullName = Players.GetUnitFullName(unitId)
        if unitFullName then
            return unitFullName
        end
    end

    return Players.GetStoredFullName(playerInfo)
end
