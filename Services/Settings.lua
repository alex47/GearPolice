local GearPolice = GearPolice

GearPolice.Settings = GearPolice.Settings or {}

local Settings = GearPolice.Settings
local PUBLIC_REPORT_MODE_MESSAGE = "Announcement mode: Activated"

Settings.ReportMode = {
    Whisper = "whisper",
    Public = "public",
    Debug = "debug",
}

Settings.PlayerListFilter = {
    All = "all",
    Problems = "problems",
    Scanning = "scanning",
    FailedPartial = "failed_partial",
}

local ReportModeDefinitions = {
    { id = Settings.ReportMode.Whisper, label = "Whisper" },
    { id = Settings.ReportMode.Public, label = "Announcement" },
    { id = Settings.ReportMode.Debug, label = "Debug" },
}

local PlayerListFilterDefinitions = {
    { id = Settings.PlayerListFilter.All, label = "All" },
    { id = Settings.PlayerListFilter.Problems, label = "Problems" },
    { id = Settings.PlayerListFilter.Scanning, label = "Scanning" },
    { id = Settings.PlayerListFilter.FailedPartial, label = "Failed/Partial" },
}

local BooleanDefaults = {
    AutomaticGroupScanEnabled = true,
    AutoWhisperInParty = false,
    AutoWhisperInRaid = true,
    DebugEnabled = false,
    HideReportOfferWhispers = false,
    PublicReportAnnouncementEnabled = true,
    PublicScanAnnouncementEnabled = false,
    PublicScanAnnouncementInParty = false,
    PublicScanAnnouncementInRaid = true,
    ReportOfferEnabled = false,
}

local function BuildOptionMetadata(definitions)
    local values = {}
    local order = {}
    local validValues = {}

    for _, definition in ipairs(definitions) do
        values[definition.id] = definition.label
        table.insert(order, definition.id)
        validValues[definition.id] = true
    end

    return values, order, validValues
end

local ReportModeValues, ReportModeOrder, ValidReportModes = BuildOptionMetadata(ReportModeDefinitions)
local PlayerListFilterValues, PlayerListFilterOrder, ValidPlayerListFilterModes =
    BuildOptionMetadata(PlayerListFilterDefinitions)

local function GetGlobalDb()
    return GearPolice.db and GearPolice.db.global or nil
end

local function GetBooleanSetting(key)
    local db = GetGlobalDb()
    if not db or type(db[key]) ~= "boolean" then
        return BooleanDefaults[key] == true
    end

    return db[key] == true
end

local function SetBooleanSetting(key, enabled)
    local db = GetGlobalDb()
    if not db or BooleanDefaults[key] == nil then
        return false
    end

    db[key] = enabled == true
    return true
end

local function EnsureEnabledChecks()
    local db = GetGlobalDb()
    if not db then
        return nil
    end

    if type(db.EnabledChecks) ~= "table" then
        db.EnabledChecks = {}
    end

    for _, ruleId in ipairs(GearPolice.Rules.GetSettingRuleIds()) do
        local rule = GearPolice.Rules.GetRuleDefinition(ruleId)
        if rule and type(db.EnabledChecks[ruleId]) ~= "boolean" then
            db.EnabledChecks[ruleId] = rule.defaultEnabled == true
        end
    end

    return db.EnabledChecks
end

local function EnsureMinimapSettings()
    local db = GetGlobalDb()
    if not db then
        return nil
    end

    if type(db.MinimapIcon) ~= "table" then
        db.MinimapIcon = {}
    end

    if type(db.MinimapIcon.hide) ~= "boolean" then
        db.MinimapIcon.hide = false
    end

    return db.MinimapIcon
end

local function GetDefaultItemLevelThreshold()
    return GearPolice.Constants.ItemLevelThreshold
end

local function NormalizeItemLevelThreshold(value)
    local threshold = tonumber(value)
    if not threshold then
        return nil
    end

    threshold = math.floor(threshold)
    if threshold < 1 then
        return nil
    end

    return threshold
end

local function AnnouncePublicReportMode()
    local chatType = GearPolice.Units.GetGroupChatType()
    if not chatType or not GearPolice.Reporting or not GearPolice.ChatThrottle then
        return
    end

    GearPolice.ChatThrottle:Send(
        GearPolice.Reporting:GetReportPrefix() .. " " .. PUBLIC_REPORT_MODE_MESSAGE,
        chatType,
        nil,
        "NORMAL"
    )
end

function Settings:Initialize()
    local db = GetGlobalDb()
    if not db then
        return
    end

    if not ValidReportModes[db.ReportMode] then
        db.ReportMode = Settings.ReportMode.Whisper
    end

    local previousRaidOnlySetting = db.AutoWhisperInRaidOnly
    if type(db.AutoWhisperInParty) ~= "boolean" and type(previousRaidOnlySetting) == "boolean" then
        db.AutoWhisperInParty = not previousRaidOnlySetting
    end
    db.AutoWhisperInRaidOnly = nil

    for key, defaultValue in pairs(BooleanDefaults) do
        if type(db[key]) ~= "boolean" then
            db[key] = defaultValue
        end
    end

    if not ValidPlayerListFilterModes[db.PlayerListFilterMode] then
        db.PlayerListFilterMode = Settings.PlayerListFilter.All
    end

    EnsureMinimapSettings()
    EnsureEnabledChecks()

    local threshold = NormalizeItemLevelThreshold(db.ItemLevelThreshold)
        or GetDefaultItemLevelThreshold()
    db.ItemLevelThreshold = threshold
    GearPolice.ItemLevelThreshold = threshold
end

function Settings:GetReportModeValues()
    return ReportModeValues
end

function Settings:GetReportModeOrder()
    return ReportModeOrder
end

function Settings:GetReportMode()
    local db = GetGlobalDb()
    local reportMode = db and db.ReportMode or nil
    return ValidReportModes[reportMode] and reportMode or Settings.ReportMode.Whisper
end

function Settings:SetReportMode(reportMode)
    if not ValidReportModes[reportMode] then
        return false
    end

    local db = GetGlobalDb()
    if not db then
        return false
    end

    local previousReportMode = self:GetReportMode()
    db.ReportMode = reportMode

    if reportMode == Settings.ReportMode.Public
        and previousReportMode ~= Settings.ReportMode.Public
        and self:IsPublicReportAnnouncementEnabled() then
        AnnouncePublicReportMode()
    end

    return true
end

function Settings:IsPublicReportAnnouncementEnabled()
    return GetBooleanSetting("PublicReportAnnouncementEnabled")
end

function Settings:IsAutomaticGroupScanEnabled()
    return GetBooleanSetting("AutomaticGroupScanEnabled")
end

function Settings:SetAutomaticGroupScanEnabled(enabled)
    local wasEnabled = self:IsAutomaticGroupScanEnabled()
    enabled = enabled == true

    if not SetBooleanSetting("AutomaticGroupScanEnabled", enabled) then
        return false
    end

    if wasEnabled == enabled then
        return true
    end

    if enabled then
        if (IsInRaid() or IsInGroup()) and GearPolice.QueueFreshGroupScan then
            GearPolice:QueueFreshGroupScan()
        end
    elseif GearPolice.CancelAutomaticGroupScans then
        GearPolice:CancelAutomaticGroupScans()
    end

    return true
end

function Settings:SetPublicReportAnnouncementEnabled(enabled)
    return SetBooleanSetting("PublicReportAnnouncementEnabled", enabled)
end

function Settings:IsPublicScanAnnouncementEnabled()
    return GetBooleanSetting("PublicScanAnnouncementEnabled")
end

function Settings:SetPublicScanAnnouncementEnabled(enabled)
    if not SetBooleanSetting("PublicScanAnnouncementEnabled", enabled) then
        return false
    end

    if not enabled and GearPolice.ClearPendingPublicScanAnnouncements then
        GearPolice:ClearPendingPublicScanAnnouncements()
    end
    if GearPolice.AnnounceCommsState then
        GearPolice:AnnounceCommsState()
    end
    return true
end

function Settings:IsPublicScanAnnouncementInPartyEnabled()
    return GetBooleanSetting("PublicScanAnnouncementInParty")
end

function Settings:SetPublicScanAnnouncementInPartyEnabled(enabled)
    if not SetBooleanSetting("PublicScanAnnouncementInParty", enabled) then
        return false
    end
    if GearPolice.AnnounceCommsState then
        GearPolice:AnnounceCommsState()
    end
    return true
end

function Settings:IsPublicScanAnnouncementInRaidEnabled()
    return GetBooleanSetting("PublicScanAnnouncementInRaid")
end

function Settings:SetPublicScanAnnouncementInRaidEnabled(enabled)
    if not SetBooleanSetting("PublicScanAnnouncementInRaid", enabled) then
        return false
    end
    if GearPolice.AnnounceCommsState then
        GearPolice:AnnounceCommsState()
    end
    return true
end

function Settings:IsReportOfferEnabled()
    return GetBooleanSetting("ReportOfferEnabled")
end

function Settings:SetReportOfferEnabled(enabled)
    if not SetBooleanSetting("ReportOfferEnabled", enabled) then
        return false
    end
    if GearPolice.AnnounceCommsState then
        GearPolice:AnnounceCommsState()
    end
    return true
end

function Settings:IsAutoWhisperInPartyEnabled()
    return GetBooleanSetting("AutoWhisperInParty")
end

function Settings:SetAutoWhisperInPartyEnabled(enabled)
    if not SetBooleanSetting("AutoWhisperInParty", enabled) then
        return false
    end
    if GearPolice.AnnounceCommsState then
        GearPolice:AnnounceCommsState()
    end
    return true
end

function Settings:IsAutoWhisperInRaidEnabled()
    return GetBooleanSetting("AutoWhisperInRaid")
end

function Settings:SetAutoWhisperInRaidEnabled(enabled)
    if not SetBooleanSetting("AutoWhisperInRaid", enabled) then
        return false
    end
    if GearPolice.AnnounceCommsState then
        GearPolice:AnnounceCommsState()
    end
    return true
end

function Settings:IsAutomaticPublicMessagingAllowedInCurrentInstance()
    local inInstance, instanceType = IsInInstance()
    return not inInstance or (instanceType ~= "pvp" and instanceType ~= "arena")
end

function Settings:IsPublicScanAnnouncementEnabledForCurrentGroup()
    if not self:IsPublicScanAnnouncementEnabled()
        or not self:IsAutomaticPublicMessagingAllowedInCurrentInstance() then
        return false
    end

    if IsInRaid() then
        return self:IsPublicScanAnnouncementInRaidEnabled()
    elseif IsInGroup() then
        return self:IsPublicScanAnnouncementInPartyEnabled()
    end

    return false
end

function Settings:IsAutoWhisperEnabledForCurrentGroup()
    if not self:IsAutomaticPublicMessagingAllowedInCurrentInstance() then
        return false
    end

    if IsInRaid() then
        return self:IsAutoWhisperInRaidEnabled()
    elseif IsInGroup() then
        return self:IsAutoWhisperInPartyEnabled()
    end

    return false
end

function Settings:GetPlayerListFilterValues()
    return PlayerListFilterValues
end

function Settings:GetPlayerListFilterOrder()
    return PlayerListFilterOrder
end

function Settings:GetPlayerListFilterMode()
    local db = GetGlobalDb()
    local filterMode = db and db.PlayerListFilterMode or nil
    return ValidPlayerListFilterModes[filterMode]
        and filterMode or Settings.PlayerListFilter.All
end

function Settings:SetPlayerListFilterMode(filterMode)
    if not ValidPlayerListFilterModes[filterMode] then
        return false
    end

    local db = GetGlobalDb()
    if not db then
        return false
    end

    db.PlayerListFilterMode = filterMode
    return true
end

function Settings:IsAutoWhispersShown()
    return not GetBooleanSetting("HideReportOfferWhispers")
end

function Settings:SetAutoWhispersShown(shown)
    return SetBooleanSetting("HideReportOfferWhispers", shown ~= true)
end

function Settings:IsDebugEnabled()
    return GetBooleanSetting("DebugEnabled")
end

function Settings:SetDebugEnabled(enabled)
    return SetBooleanSetting("DebugEnabled", enabled)
end

function Settings:IsMinimapIconShown()
    local minimapSettings = EnsureMinimapSettings()
    return not minimapSettings or minimapSettings.hide ~= true
end

function Settings:SetMinimapIconShown(shown)
    local minimapSettings = EnsureMinimapSettings()
    if not minimapSettings then
        return false
    end

    minimapSettings.hide = shown ~= true

    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    if LibDBIcon then
        if shown then
            LibDBIcon:Show(GearPolice.AddonName)
        else
            LibDBIcon:Hide(GearPolice.AddonName)
        end
    end

    return true
end

function Settings:IsRuleEnabled(ruleId)
    local rule = GearPolice.Rules.GetRuleDefinition(ruleId)
    if not rule or type(rule.defaultEnabled) ~= "boolean" then
        return true
    end

    local enabledChecks = EnsureEnabledChecks()
    if not enabledChecks then
        return rule.defaultEnabled == true
    end

    return enabledChecks[ruleId] == true
end

function Settings:SetRuleEnabled(ruleId, enabled)
    local rule = GearPolice.Rules.GetRuleDefinition(ruleId)
    if not rule or type(rule.defaultEnabled) ~= "boolean" then
        return false
    end

    local enabledChecks = EnsureEnabledChecks()
    if not enabledChecks then
        return false
    end

    enabledChecks[ruleId] = enabled == true
    return true
end

function Settings:GetItemLevelThreshold()
    local db = GetGlobalDb()
    return NormalizeItemLevelThreshold(db and db.ItemLevelThreshold or nil)
        or GetDefaultItemLevelThreshold()
end

function Settings:SetItemLevelThreshold(value)
    local threshold = NormalizeItemLevelThreshold(value)
    local db = GetGlobalDb()
    if not threshold or not db then
        return false
    end

    db.ItemLevelThreshold = threshold
    GearPolice.ItemLevelThreshold = threshold
    return true
end

function GearPolice:InitializeSettings()
    return Settings:Initialize()
end
