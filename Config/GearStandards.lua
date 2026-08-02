local GearPolice = GearPolice

GearPolice.GearStandards = GearPolice.GearStandards or {}

local GearStandards = GearPolice.GearStandards

GearStandards.MinimumArmorSpecializationLevel = 50
GearStandards.MinimumSpecializationLevel = 10
GearStandards.ArmorItemClassId = 4

GearStandards.PrimaryStat = {
    Strength = "strength",
    Agility = "agility",
    Intellect = "intellect",
}

local ArmorTypesBySubclassId = {
    [1] = "Cloth",
    [2] = "Leather",
    [3] = "Mail",
    [4] = "Plate",
}

local PreferredArmorByClass = {
    DEATHKNIGHT = "Plate",
    DRUID = "Leather",
    HUNTER = "Mail",
    MAGE = "Cloth",
    MONK = "Leather",
    PALADIN = "Plate",
    PRIEST = "Cloth",
    ROGUE = "Leather",
    SHAMAN = "Mail",
    WARLOCK = "Cloth",
    WARRIOR = "Plate",
}

local ArmorSpecializationSlotNames = {
    "HeadSlot",
    "ShoulderSlot",
    "ChestSlot",
    "WristSlot",
    "HandsSlot",
    "WaistSlot",
    "LegsSlot",
    "FeetSlot",
}

local ArmorSpecializationSlots = {}
for _, slotName in ipairs(ArmorSpecializationSlotNames) do
    ArmorSpecializationSlots[slotName] = true
end

local PrimaryStatDefinitions = {
    [GearStandards.PrimaryStat.Strength] = {
        itemStatKey = "ITEM_MOD_STRENGTH_SHORT",
        label = "Strength",
    },
    [GearStandards.PrimaryStat.Agility] = {
        itemStatKey = "ITEM_MOD_AGILITY_SHORT",
        label = "Agility",
    },
    [GearStandards.PrimaryStat.Intellect] = {
        itemStatKey = "ITEM_MOD_INTELLECT_SHORT",
        label = "Intellect",
    },
}

local OrderedPrimaryStats = {
    GearStandards.PrimaryStat.Strength,
    GearStandards.PrimaryStat.Agility,
    GearStandards.PrimaryStat.Intellect,
}

local PreferredPrimaryStatBySpecialization = {
    -- Death Knight
    [250] = GearStandards.PrimaryStat.Strength,
    [251] = GearStandards.PrimaryStat.Strength,
    [252] = GearStandards.PrimaryStat.Strength,

    -- Druid
    [102] = GearStandards.PrimaryStat.Intellect,
    [103] = GearStandards.PrimaryStat.Agility,
    [104] = GearStandards.PrimaryStat.Agility,
    [105] = GearStandards.PrimaryStat.Intellect,

    -- Hunter
    [253] = GearStandards.PrimaryStat.Agility,
    [254] = GearStandards.PrimaryStat.Agility,
    [255] = GearStandards.PrimaryStat.Agility,

    -- Mage
    [62] = GearStandards.PrimaryStat.Intellect,
    [63] = GearStandards.PrimaryStat.Intellect,
    [64] = GearStandards.PrimaryStat.Intellect,

    -- Monk
    [268] = GearStandards.PrimaryStat.Agility,
    [269] = GearStandards.PrimaryStat.Agility,
    [270] = GearStandards.PrimaryStat.Intellect,

    -- Paladin
    [65] = GearStandards.PrimaryStat.Intellect,
    [66] = GearStandards.PrimaryStat.Strength,
    [70] = GearStandards.PrimaryStat.Strength,

    -- Priest
    [256] = GearStandards.PrimaryStat.Intellect,
    [257] = GearStandards.PrimaryStat.Intellect,
    [258] = GearStandards.PrimaryStat.Intellect,

    -- Rogue
    [259] = GearStandards.PrimaryStat.Agility,
    [260] = GearStandards.PrimaryStat.Agility,
    [261] = GearStandards.PrimaryStat.Agility,

    -- Shaman
    [262] = GearStandards.PrimaryStat.Intellect,
    [263] = GearStandards.PrimaryStat.Agility,
    [264] = GearStandards.PrimaryStat.Intellect,

    -- Warlock
    [265] = GearStandards.PrimaryStat.Intellect,
    [266] = GearStandards.PrimaryStat.Intellect,
    [267] = GearStandards.PrimaryStat.Intellect,

    -- Warrior
    [71] = GearStandards.PrimaryStat.Strength,
    [72] = GearStandards.PrimaryStat.Strength,
    [73] = GearStandards.PrimaryStat.Strength,
}

local PreferredPrimaryStatBySingleStatClass = {
    DEATHKNIGHT = GearStandards.PrimaryStat.Strength,
    HUNTER = GearStandards.PrimaryStat.Agility,
    MAGE = GearStandards.PrimaryStat.Intellect,
    PRIEST = GearStandards.PrimaryStat.Intellect,
    ROGUE = GearStandards.PrimaryStat.Agility,
    WARLOCK = GearStandards.PrimaryStat.Intellect,
    WARRIOR = GearStandards.PrimaryStat.Strength,
}

function GearStandards.GetPreferredArmorType(classFile)
    return classFile and PreferredArmorByClass[classFile] or nil
end

function GearStandards.GetArmorTypeBySubclassId(subclassId)
    return ArmorTypesBySubclassId[tonumber(subclassId)]
end

function GearStandards.GetArmorTypeByName(itemSubType)
    for _, armorType in pairs(ArmorTypesBySubclassId) do
        if itemSubType == armorType then
            return armorType
        end
    end

    return nil
end

function GearStandards.GetArmorSpecializationSlotNames()
    return ArmorSpecializationSlotNames
end

function GearStandards.IsArmorSpecializationSlot(slotName)
    return slotName and ArmorSpecializationSlots[slotName] == true
end

function GearStandards.GetPreferredPrimaryStat(specializationId, classFile)
    local primaryStat = PreferredPrimaryStatBySpecialization[tonumber(specializationId)]
    if primaryStat then
        return primaryStat
    end

    return classFile and PreferredPrimaryStatBySingleStatClass[classFile] or nil
end

function GearStandards.GetOrderedPrimaryStats()
    return OrderedPrimaryStats
end

function GearStandards.GetPrimaryStatDefinition(primaryStat)
    return primaryStat and PrimaryStatDefinitions[primaryStat] or nil
end

function GearStandards.GetPrimaryStatLabel(primaryStat)
    local definition = GearStandards.GetPrimaryStatDefinition(primaryStat)
    return definition and definition.label or nil
end
