local GearPolice = GearPolice

local UI = GearPolice.UI

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

local function BuildScopeGroup(config)
    return {
        type = "group",
        name = "",
        inline = true,
        order = config.order,
        args = {
            indent = {
                type = "description",
                name = " ",
                order = 10,
                width = 0.15,
            },
            party = {
                type = "toggle",
                name = config.partyLabel,
                desc = config.partyDescription,
                order = 20,
                width = "normal",
                disabled = config.disabled,
                get = config.getParty,
                set = config.setParty,
            },
            raid = {
                type = "toggle",
                name = config.raidLabel,
                desc = config.raidDescription,
                order = 30,
                width = "normal",
                disabled = config.disabled,
                get = config.getRaid,
                set = config.setRaid,
            },
        },
    }
end

local function BuildRuleToggle(ruleId, width)
    local rule = GearPolice.Rules.GetRuleDefinition(ruleId)
    return {
        type = "toggle",
        name = rule.settingLabel,
        desc = rule.settingDescription,
        order = rule.settingOrder,
        width = width or "full",
        get = function()
            return GetRule(ruleId)
        end,
        set = function(_info, value)
            SetRule(ruleId, value)
        end,
    }
end

local function BuildCheckOptions()
    local options = {}

    for _, ruleId in ipairs(GearPolice.Rules.GetSettingRuleIds()) do
        if ruleId ~= "low_item_level" then
            options[ruleId] = BuildRuleToggle(ruleId)
        end
    end

    options.low_item_level = BuildRuleToggle("low_item_level", "normal")
    options.lowItemLevelThreshold = {
        type = "input",
        name = "",
        desc = "Items below this item level are reported when Low Item Level is enabled.",
        order = GearPolice.Rules.GetRuleDefinition("low_item_level").settingOrder + 1,
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
    }

    return options
end

local function BuildOptions()
    return {
        type = "group",
        name = GearPolice.AddonName,
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
                                values = GetSettings():GetReportModeValues(),
                                sorting = GetSettings():GetReportModeOrder(),
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
                                desc = "After a successful scan finds issues, announce the grouped player's "
                                    .. "total and per-issue counts in party or raid chat.",
                                order = 20,
                                width = "full",
                                get = function()
                                    return GetSettings():IsPublicScanAnnouncementEnabled()
                                end,
                                set = function(_info, value)
                                    GetSettings():SetPublicScanAnnouncementEnabled(value)
                                end,
                            },
                            publicScanAnnouncementScopes = BuildScopeGroup({
                                order = 30,
                                partyLabel = "Auto-Announce In Party",
                                partyDescription =
                                    "Send automatic scan issue summaries while you are in a party.",
                                raidLabel = "Auto-Announce In Raid",
                                raidDescription =
                                    "Send automatic scan issue summaries while you are in a raid.",
                                disabled = function()
                                    return not GetSettings():IsPublicScanAnnouncementEnabled()
                                end,
                                getParty = function()
                                    return GetSettings():IsPublicScanAnnouncementInPartyEnabled()
                                end,
                                setParty = function(_info, value)
                                    GetSettings():SetPublicScanAnnouncementInPartyEnabled(value)
                                end,
                                getRaid = function()
                                    return GetSettings():IsPublicScanAnnouncementInRaidEnabled()
                                end,
                                setRaid = function(_info, value)
                                    GetSettings():SetPublicScanAnnouncementInRaidEnabled(value)
                                end,
                            }),
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
                                    .. "issues. The offer shows the total and per-issue counts and invites them "
                                    .. "to request the full report with !gp.",
                                order = 20,
                                width = "full",
                                get = function()
                                    return GetSettings():IsReportOfferEnabled()
                                end,
                                set = function(_info, value)
                                    GetSettings():SetReportOfferEnabled(value)
                                end,
                            },
                            reportOfferScopes = BuildScopeGroup({
                                order = 30,
                                partyLabel = "Auto-Whisper In Party",
                                partyDescription =
                                    "Send automatic report offer whispers while you are in a party.",
                                raidLabel = "Auto-Whisper In Raid",
                                raidDescription =
                                    "Send automatic report offer whispers while you are in a raid.",
                                disabled = function()
                                    return not GetSettings():IsReportOfferEnabled()
                                end,
                                getParty = function()
                                    return GetSettings():IsAutoWhisperInPartyEnabled()
                                end,
                                setParty = function(_info, value)
                                    GetSettings():SetAutoWhisperInPartyEnabled(value)
                                end,
                                getRaid = function()
                                    return GetSettings():IsAutoWhisperInRaidEnabled()
                                end,
                                setRaid = function(_info, value)
                                    GetSettings():SetAutoWhisperInRaidEnabled(value)
                                end,
                            }),
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
                args = BuildCheckOptions(),
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

    AceConfig:RegisterOptionsTable(GearPolice.AddonName, BuildOptions())
    local _, categoryId = AceConfigDialog:AddToBlizOptions(
        GearPolice.AddonName,
        GearPolice.AddonName
    )
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
