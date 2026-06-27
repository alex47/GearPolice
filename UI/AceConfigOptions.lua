local GearPolice = GearPolice

local UI = GearPolice.UI

local AddonName = "GearPolice"

local ReportModeValues = {
    whisper = "Whisper",
    public = "Public",
    debug = "Debug",
}

local ReportModeOrder = {
    "whisper",
    "public",
    "debug",
}

local function GetSettings()
    return GearPolice.Settings
end

local function GetRule(ruleId)
    return GetSettings():IsRuleEnabled(ruleId)
end

local function SetRule(ruleId, enabled)
    GetSettings():SetRuleEnabled(ruleId, enabled)
end

local function ValidateItemLevelThreshold(_info, value)
    local threshold = tonumber(value)
    if not threshold then
        return "Low Item Level Threshold must be a number."
    end

    threshold = math.floor(threshold)
    if threshold < 1 then
        return "Low Item Level Threshold must be at least 1."
    end

    return true
end

local function BuildOptions()
    return {
        type = "group",
        name = "GearPolice",
        args = {
            general = {
                type = "group",
                name = "General",
                inline = true,
                order = 10,
                args = {
                    showMinimapButton = {
                        type = "toggle",
                        name = "Show Minimap Button",
                        desc = "Show or hide the GearPolice minimap button.",
                        order = 10,
                        get = function()
                            return GetSettings():IsMinimapIconShown()
                        end,
                        set = function(_info, value)
                            GetSettings():SetMinimapIconShown(value)
                        end,
                    },
                },
            },
            reporting = {
                type = "group",
                name = "Reporting",
                inline = true,
                order = 20,
                args = {
                    manualReportMode = {
                        type = "select",
                        name = "Manual Report Mode",
                        desc = "Choose where the row report button sends manual reports.",
                        order = 10,
                        values = ReportModeValues,
                        sorting = ReportModeOrder,
                        get = function()
                            return GetSettings():GetReportMode()
                        end,
                        set = function(_info, value)
                            GetSettings():SetReportMode(value)
                        end,
                    },
                    reportOffers = {
                        type = "toggle",
                        name = "Auto-Whisper After Scan Completes",
                        desc = "Automatically whisper grouped players with issues after their scan finishes.",
                        order = 20,
                        width = "full",
                        get = function()
                            return GetSettings():IsReportOfferEnabled()
                        end,
                        set = function(_info, value)
                            GetSettings():SetReportOfferEnabled(value)
                        end,
                    },
                    showAutoWhispers = {
                        type = "toggle",
                        name = "Show Auto-Whispers",
                        desc = "Show GearPolice automatic offer and reply whispers in your local chat window.",
                        order = 30,
                        width = "full",
                        get = function()
                            return GetSettings():IsAutoWhispersShown()
                        end,
                        set = function(_info, value)
                            GetSettings():SetAutoWhispersShown(value)
                        end,
                    },
                },
            },
            checks = {
                type = "group",
                name = "Checks",
                inline = true,
                order = 30,
                args = {
                    missingGems = {
                        type = "toggle",
                        name = "Missing Gems",
                        order = 10,
                        width = "full",
                        get = function()
                            return GetRule("missing_gems")
                        end,
                        set = function(_info, value)
                            SetRule("missing_gems", value)
                        end,
                    },
                    missingEnchants = {
                        type = "toggle",
                        name = "Missing Enchants",
                        order = 20,
                        width = "full",
                        get = function()
                            return GetRule("missing_enchant")
                        end,
                        set = function(_info, value)
                            SetRule("missing_enchant", value)
                        end,
                    },
                    missingUpgrades = {
                        type = "toggle",
                        name = "Missing Upgrades",
                        order = 30,
                        width = "full",
                        get = function()
                            return GetRule("missing_upgrade")
                        end,
                        set = function(_info, value)
                            SetRule("missing_upgrade", value)
                        end,
                    },
                    missingWaistExtraGem = {
                        type = "toggle",
                        name = "Missing Extra Waist Gem Socket",
                        order = 40,
                        width = "full",
                        get = function()
                            return GetRule("missing_waist_extra_gem")
                        end,
                        set = function(_info, value)
                            SetRule("missing_waist_extra_gem", value)
                        end,
                    },
                    missingEnchanterRingEnchant = {
                        type = "toggle",
                        name = "Missing Enchant On One Ring",
                        desc = "If one ring is enchanted, report the other ring when it is not enchanted.",
                        order = 50,
                        width = "full",
                        get = function()
                            return GetRule("missing_enchanter_ring_enchant")
                        end,
                        set = function(_info, value)
                            SetRule("missing_enchanter_ring_enchant", value)
                        end,
                    },
                    lowItemLevelGroup = {
                        type = "group",
                        name = "Low Item Level",
                        inline = true,
                        order = 60,
                        args = {
                            enabled = {
                                type = "toggle",
                                name = "Enable Check",
                                order = 10,
                                width = "full",
                                get = function()
                                    return GetRule("low_item_level")
                                end,
                                set = function(_info, value)
                                    SetRule("low_item_level", value)
                                end,
                            },
                            threshold = {
                                type = "input",
                                name = "Threshold",
                                desc = "Items below this item level are reported when Low Item Level is enabled.",
                                order = 20,
                                width = "double",
                                validate = ValidateItemLevelThreshold,
                                disabled = function()
                                    return not GetRule("low_item_level")
                                end,
                                get = function()
                                    return tostring(GetSettings():GetItemLevelThreshold())
                                end,
                                set = function(_info, value)
                                    GetSettings():SetItemLevelThreshold(value)
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
end

function UI:RegisterAceConfigSettings()
    if self.AceConfigSettingsRegistered then
        return
    end

    local AceConfig = LibStub("AceConfig-3.0", true)
    local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
    if not AceConfig or not AceConfigDialog then
        return
    end

    AceConfig:RegisterOptionsTable(AddonName, BuildOptions())
    local _, categoryId = AceConfigDialog:AddToBlizOptions(AddonName, "GearPolice")
    self.AceConfigCategoryId = categoryId
    self.AceConfigSettingsRegistered = true
end

function UI:OpenAceConfigSettings()
    if not self.AceConfigCategoryId then
        self:RegisterAceConfigSettings()
    end

    local blizzardSettings = _G.Settings
    if blizzardSettings and blizzardSettings.OpenToCategory and self.AceConfigCategoryId then
        blizzardSettings.OpenToCategory(self.AceConfigCategoryId)
    end
end
