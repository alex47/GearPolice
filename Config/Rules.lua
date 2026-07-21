local GearPolice = GearPolice

GearPolice.Rules = GearPolice.Rules or {}

local Rules = GearPolice.Rules

local RuleDefinitions = {
    missing_gems = {
        message = "Missing Gem",
        evaluate = function(itemLink)
            return GearPolice.Inspection:IsItemMissingGems(itemLink)
        end,
    },
    missing_enchant = {
        message = "Missing Enchant",
        evaluate = function(itemLink)
            return GearPolice.Inspection:IsItemMissingEnchant(itemLink)
        end,
    },
    missing_waist_extra_gem = {
        message = "Missing Extra Waist Gem Enchant",
        evaluate = function(itemLink)
            return GearPolice.Inspection:IsWaistMissingExtraGemEnchant(itemLink)
        end,
    },
    missing_upgrade = {
        message = "Missing Upgrade",
        evaluate = function(itemLink, context)
            return GearPolice.Inspection:GetMissingUpgradeResult(itemLink, context.unitId, context.slotID)
        end,
        buildMessage = function(_, _, checkResult)
            if type(checkResult) ~= "table" then
                return "Missing Upgrade"
            end

            local currentUpgrade = tonumber(checkResult.currentUpgrade)
            local maximumUpgrade = tonumber(checkResult.maximumUpgrade)
            if not currentUpgrade or not maximumUpgrade then
                return "Missing Upgrade"
            end

            return ("Missing Upgrade (%d/%d)"):format(currentUpgrade, maximumUpgrade)
        end,
    },
    low_item_level = {
        message = "Low Item Level",
        evaluate = function(itemLink)
            return GearPolice.Inspection:IsItemBelowItemLevel(itemLink)
        end,
        buildMessage = function()
            return "Low Item Level (below "
                .. tostring(GearPolice.Settings:GetItemLevelThreshold())
                .. ")"
        end,
    },
}

local SlotRuleIds = {
    -- Head enchants are intentionally omitted while there are none in the current game phase.
    HeadSlot          = { "missing_gems",                       "low_item_level", "missing_upgrade" },
    NeckSlot          = { "missing_gems",                       "low_item_level", "missing_upgrade" },
    ShoulderSlot      = { "missing_gems", "missing_enchant",    "low_item_level", "missing_upgrade" },
    BackSlot          = { "missing_gems", "missing_enchant",    "low_item_level", "missing_upgrade" },
    ChestSlot         = { "missing_gems", "missing_enchant",    "low_item_level", "missing_upgrade" },
    WristSlot         = { "missing_gems", "missing_enchant",    "low_item_level", "missing_upgrade" },
    HandsSlot         = { "missing_gems", "missing_enchant",    "low_item_level", "missing_upgrade" },
    WaistSlot         = {
        "missing_gems",
        "low_item_level",
        "missing_waist_extra_gem",
        "missing_upgrade",
    },
    LegsSlot          = { "missing_gems", "missing_enchant",    "low_item_level", "missing_upgrade" },
    FeetSlot          = { "missing_gems", "missing_enchant",    "low_item_level", "missing_upgrade" },
    Finger0Slot       = { "missing_gems",                       "low_item_level", "missing_upgrade" },
    Finger1Slot       = { "missing_gems",                       "low_item_level", "missing_upgrade" },
    MainHandSlot      = { "missing_gems", "missing_enchant",    "low_item_level", "missing_upgrade" },
    SecondaryHandSlot = { "missing_gems", "missing_enchant",    "low_item_level", "missing_upgrade" },
    Trinket0Slot      = { "missing_gems",                       "low_item_level", "missing_upgrade" },
    Trinket1Slot      = { "missing_gems",                       "low_item_level", "missing_upgrade" },
}

function Rules.GetRuleDefinitions()
    return RuleDefinitions
end

function Rules.GetSlotRuleIds()
    return SlotRuleIds
end

function Rules.GetSlotRuleIdsForSlot(slotName)
    return SlotRuleIds[slotName]
end
