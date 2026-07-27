local GearPolice = GearPolice

GearPolice.Tables = GearPolice.Tables or {}
GearPolice.Helper = GearPolice.Helper or {}

local Tables = GearPolice.Tables
local Helper = GearPolice.Helper

-- Compatibility-only utility; production code should use its owning module directly.
function Tables.Contains(values, value)
    for _, currentValue in pairs(values) do
        if currentValue == value then return true end
    end

    return false
end

function Helper:tContains(values, value)
    return Tables.Contains(values, value)
end
