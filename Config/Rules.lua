local GearPolice = GearPolice

GearPolice.Rules = GearPolice.Rules or {}

local Rules = GearPolice.Rules

Rules.EnchanterRingEnchantRuleId = "missing_enchanter_ring_enchant"

local RuleDefinitions = {
    missing_gems = {
        message = "Missing Gem",
        defaultEnabled = true,
        settingLabel = "Missing Gems",
        settingDescription = "Report items with one or more empty gem sockets.",
        settingOrder = 10,
        summaryOrder = 10,
        evaluate = function(itemLink)
            return GearPolice.Inspection:IsItemMissingGems(itemLink)
        end,
    },
    missing_enchant = {
        message = "Missing Enchant",
        defaultEnabled = true,
        settingLabel = "Missing Enchants",
        settingDescription = "Report configured equipment slots that do not have an enchant.",
        settingOrder = 20,
        summaryOrder = 20,
        evaluate = function(itemLink)
            return GearPolice.Inspection:IsItemMissingEnchant(itemLink)
        end,
    },
    missing_waist_extra_gem = {
        message = "Missing Extra Waist Gem Enchant",
        summaryLabel = "Missing Extra Waist Gem Socket",
        defaultEnabled = true,
        settingLabel = "Missing Extra Waist Gem Socket",
        settingDescription = "Report waist items whose normal sockets are filled but have no extra belt-buckle gem.",
        settingOrder = 40,
        summaryOrder = 40,
        evaluate = function(itemLink)
            return GearPolice.Inspection:IsWaistMissingExtraGemEnchant(itemLink)
        end,
    },
    missing_upgrade = {
        message = "Missing Upgrade",
        defaultEnabled = true,
        settingLabel = "Missing Upgrades",
        settingDescription = "Report upgradeable items that are not at their maximum upgrade level.",
        settingOrder = 30,
        summaryOrder = 30,
        evaluate = function(itemLink, context)
            return GearPolice.Inspection:GetMissingUpgradeResult(itemLink, context.unitId, context.slotID)
        end,
        buildMessage = function(_, _, checkResult, rule)
            if type(checkResult) ~= "table" then
                return rule.message
            end

            local currentUpgrade = tonumber(checkResult.currentUpgrade)
            local maximumUpgrade = tonumber(checkResult.maximumUpgrade)
            if not currentUpgrade or not maximumUpgrade then
                return rule.message
            end

            return ("%s (%d/%d)"):format(rule.message, currentUpgrade, maximumUpgrade)
        end,
    },
    low_item_level = {
        message = "Low Item Level",
        defaultEnabled = true,
        settingLabel = "Low Item Level",
        settingDescription = "Report items below the configured item level threshold.",
        settingOrder = 60,
        summaryOrder = 60,
        evaluate = function(itemLink)
            return GearPolice.Inspection:IsItemBelowItemLevel(itemLink)
        end,
        buildMessage = function()
            return "Low Item Level (Below "
                .. tostring(GearPolice.Settings:GetItemLevelThreshold())
                .. ")"
        end,
    },
    missing_enchanter_ring_enchant = {
        message = "Missing Enchanter Ring Enchant",
        defaultEnabled = true,
        settingLabel = "Missing Enchant On One Ring",
        settingDescription = "If one ring is enchanted, report the other ring when it is not enchanted.",
        settingOrder = 50,
        summaryOrder = 50,
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

local function GetOrderedRuleIds(orderField)
    local orderedRules = {}

    for ruleId, rule in pairs(RuleDefinitions) do
        if type(rule[orderField]) == "number" then
            table.insert(orderedRules, {
                ruleId = ruleId,
                order = rule[orderField],
            })
        end
    end

    table.sort(orderedRules, function(left, right)
        if left.order == right.order then
            return left.ruleId < right.ruleId
        end

        return left.order < right.order
    end)

    local ruleIds = {}
    for _, orderedRule in ipairs(orderedRules) do
        table.insert(ruleIds, orderedRule.ruleId)
    end

    return ruleIds
end

function Rules.GetRuleDefinition(ruleId)
    return RuleDefinitions[ruleId]
end

function Rules.GetIssueSummaryRuleIds()
    return GetOrderedRuleIds("summaryOrder")
end

function Rules.GetIssueSummaryLabel(ruleId)
    local rule = RuleDefinitions[ruleId]
    if not rule then
        return nil
    end

    return rule.summaryLabel or rule.message
end

function Rules.GetIssueSummaryOrder(ruleId)
    local rule = RuleDefinitions[ruleId]
    return rule and rule.summaryOrder or nil
end

function Rules.GetSettingRuleIds()
    return GetOrderedRuleIds("settingOrder")
end

function Rules.GetSlotRuleIdsForSlot(slotName)
    return SlotRuleIds[slotName]
end
