local GearPolice = GearPolice

local UI = GearPolice.UI

local AddonName = "GearPolice"

local ReportModeValues = {
    whisper = "Whisper",
    public = "Announcement",
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
                order = 30,
                args = {
                    manualReporting = {
                        type = "group",
                        name = "Manual Reporting",
                        inline = true,
                        order = 10,
                        args = {
                            manualReportMode = {
                                type = "select",
                                name = "Manual Report Mode",
                                desc = "Choose where each player's speaker button sends the manual report.",
                                order = 10,
                                width = "normal",
                                values = ReportModeValues,
                                sorting = ReportModeOrder,
                                get = function()
                                    return GetSettings():GetReportMode()
                                end,
                                set = function(_info, value)
                                    GetSettings():SetReportMode(value)
                                end,
                            },
                        },
                    },
                    automaticAnnouncements = {
                        type = "group",
                        name = "Automatic Announcements",
                        inline = true,
                        order = 20,
                        args = {
                            publicReportAnnouncement = {
                                type = "toggle",
                                name = "Announce Changing To Manual Announcement Mode",
                                desc = "Announce in party or raid chat when Manual Report Mode is changed "
                                    .. "to Announcement.",
                                order = 10,
                                width = "full",
                                get = function()
                                    return GetSettings():IsPublicReportAnnouncementEnabled()
                                end,
                                set = function(_info, value)
                                    GetSettings():SetPublicReportAnnouncementEnabled(value)
                                end,
                            },
                            publicScanAnnouncement = {
                                type = "toggle",
                                name = "Auto-Announce Summary Per Player",
                                desc = "Announce a grouped player's issue count in party or raid chat after a "
                                    .. "successful scan.",
                                order = 20,
                                width = "full",
                                get = function()
                                    return GetSettings():IsPublicScanAnnouncementEnabled()
                                end,
                                set = function(_info, value)
                                    GetSettings():SetPublicScanAnnouncementEnabled(value)
                                end,
                            },
                            publicScanAnnouncementScopes = {
                                type = "group",
                                name = "",
                                inline = true,
                                order = 30,
                                args = {
                                    indent = {
                                        type = "description",
                                        name = " ",
                                        order = 10,
                                        width = 0.15,
                                    },
                                    party = {
                                        type = "toggle",
                                        name = "Auto-Announce In Party",
                                        desc = "Send automatic scan issue summaries while you are in a party.",
                                        order = 20,
                                        width = "normal",
                                        disabled = function()
                                            return not GetSettings():IsPublicScanAnnouncementEnabled()
                                        end,
                                        get = function()
                                            return GetSettings():IsPublicScanAnnouncementInPartyEnabled()
                                        end,
                                        set = function(_info, value)
                                            GetSettings():SetPublicScanAnnouncementInPartyEnabled(value)
                                        end,
                                    },
                                    raid = {
                                        type = "toggle",
                                        name = "Auto-Announce In Raid",
                                        desc = "Send automatic scan issue summaries while you are in a raid.",
                                        order = 30,
                                        width = "normal",
                                        disabled = function()
                                            return not GetSettings():IsPublicScanAnnouncementEnabled()
                                        end,
                                        get = function()
                                            return GetSettings():IsPublicScanAnnouncementInRaidEnabled()
                                        end,
                                        set = function(_info, value)
                                            GetSettings():SetPublicScanAnnouncementInRaidEnabled(value)
                                        end,
                                    },
                                },
                            },
                        },
                    },
                    automaticWhispers = {
                        type = "group",
                        name = "Automatic Whispers",
                        inline = true,
                        order = 30,
                        args = {
                            reportOffers = {
                                type = "toggle",
                                name = "Auto-Whisper Report Offer",
                                desc = "Automatically whisper other group members when a successful scan finds "
                                    .. "issues, inviting them to request the full report with !gp.",
                                order = 20,
                                width = "full",
                                get = function()
                                    return GetSettings():IsReportOfferEnabled()
                                end,
                                set = function(_info, value)
                                    GetSettings():SetReportOfferEnabled(value)
                                end,
                            },
                            reportOfferScopes = {
                                type = "group",
                                name = "",
                                inline = true,
                                order = 30,
                                args = {
                                    indent = {
                                        type = "description",
                                        name = " ",
                                        order = 10,
                                        width = 0.15,
                                    },
                                    party = {
                                        type = "toggle",
                                        name = "Auto-Whisper In Party",
                                        desc = "Send automatic report offer whispers while you are in a party.",
                                        order = 20,
                                        width = "normal",
                                        disabled = function()
                                            return not GetSettings():IsReportOfferEnabled()
                                        end,
                                        get = function()
                                            return GetSettings():IsAutoWhisperInPartyEnabled()
                                        end,
                                        set = function(_info, value)
                                            GetSettings():SetAutoWhisperInPartyEnabled(value)
                                        end,
                                    },
                                    raid = {
                                        type = "toggle",
                                        name = "Auto-Whisper In Raid",
                                        desc = "Send automatic report offer whispers while you are in a raid.",
                                        order = 30,
                                        width = "normal",
                                        disabled = function()
                                            return not GetSettings():IsReportOfferEnabled()
                                        end,
                                        get = function()
                                            return GetSettings():IsAutoWhisperInRaidEnabled()
                                        end,
                                        set = function(_info, value)
                                            GetSettings():SetAutoWhisperInRaidEnabled(value)
                                        end,
                                    },
                                },
                            },
                            showAutoWhispers = {
                                type = "toggle",
                                name = "Show Auto-Whispers",
                                desc = "Show !gp requests and GearPolice's automatic report offer and reply "
                                    .. "whispers in your chat window.",
                                order = 10,
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
                },
            },
            checks = {
                type = "group",
                name = "Checks",
                inline = true,
                order = 20,
                args = {
                    missingGems = {
                        type = "toggle",
                        name = "Missing Gems",
                        desc = "Report items with one or more empty gem sockets.",
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
                        desc = "Report configured equipment slots that do not have an enchant.",
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
                        desc = "Report upgradeable items that are not at their maximum upgrade level.",
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
                        desc = "Report waist items whose normal sockets are filled but have no extra belt-buckle gem.",
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
                    lowItemLevel = {
                        type = "toggle",
                        name = "Low Item Level",
                        desc = "Report items below the configured item level threshold.",
                        order = 60,
                        width = "normal",
                        get = function()
                            return GetRule("low_item_level")
                        end,
                        set = function(_info, value)
                            SetRule("low_item_level", value)
                        end,
                    },
                    lowItemLevelThreshold = {
                        type = "input",
                        name = "",
                        desc = "Items below this item level are reported when Low Item Level is enabled.",
                        order = 61,
                        width = "normal",
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
    if self.uiFrame then
        self:HideUI()
    end

    if not self.AceConfigCategoryId then
        self:RegisterAceConfigSettings()
    end

    local blizzardSettings = _G.Settings
    if blizzardSettings and blizzardSettings.OpenToCategory and self.AceConfigCategoryId then
        blizzardSettings.OpenToCategory(self.AceConfigCategoryId)
    end
end
