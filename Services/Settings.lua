local GearPolice = GearPolice

GearPolice.Settings = GearPolice.Settings or {}

local Settings = GearPolice.Settings
local PUBLIC_REPORT_MODE_MESSAGE = "Public Shaming mode: Activated"

local ReportModes = {
    whisper = true,
    public = true,
    debug = true,
}

local CheckDefaults = {
    missing_gems = true,
    missing_enchant = true,
    missing_upgrade = true,
    missing_waist_extra_gem = true,
    low_item_level = true,
    missing_enchanter_ring_enchant = true,
}

local function GetGlobalDb()
    return GearPolice.db and GearPolice.db.global or nil
end

local function EnsureEnabledChecks()
    local db = GetGlobalDb()
    if not db then
        return nil
    end

    if type(db.EnabledChecks) ~= "table" then
        db.EnabledChecks = {}
    end

    for ruleId, defaultValue in pairs(CheckDefaults) do
        if type(db.EnabledChecks[ruleId]) ~= "boolean" then
            db.EnabledChecks[ruleId] = defaultValue
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
    return GearPolice.Constants and GearPolice.Constants.ItemLevelThreshold or 450
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
    if not GearPolice.Reporting or not GearPolice.ChatThrottle then
        return
    end

    if not IsInGroup() then
        return
    end

    local reportPrefix = GearPolice.Reporting:GetReportPrefix()
    GearPolice.ChatThrottle:Send(
        reportPrefix .. " " .. PUBLIC_REPORT_MODE_MESSAGE,
        IsInRaid() and "RAID" or "PARTY",
        nil,
        "NORMAL"
    )
end

function Settings:Initialize()
    local db = GetGlobalDb()
    if not db then
        return
    end

    if not ReportModes[db.ReportMode] then
        db.ReportMode = "whisper"
    end

    if type(db.AutoWhisperInRaidOnly) ~= "boolean" then
        db.AutoWhisperInRaidOnly = true
    end

    if type(db.PublicReportAnnouncementEnabled) ~= "boolean" then
        db.PublicReportAnnouncementEnabled = true
    end

    EnsureMinimapSettings()
    EnsureEnabledChecks()

    local threshold = NormalizeItemLevelThreshold(db.ItemLevelThreshold)
    if not threshold then
        threshold = GetDefaultItemLevelThreshold()
    end

    db.ItemLevelThreshold = threshold
    GearPolice.ItemLevelThreshold = threshold
end

function Settings:GetReportMode()
    local db = GetGlobalDb()
    local reportMode = db and db.ReportMode or nil
    if ReportModes[reportMode] then
        return reportMode
    end

    return "whisper"
end

function Settings:SetReportMode(reportMode)
    if not ReportModes[reportMode] then
        return false
    end

    local db = GetGlobalDb()
    if not db then
        return false
    end

    local previousReportMode = self:GetReportMode()
    db.ReportMode = reportMode

    if reportMode == "public" and previousReportMode ~= "public"
        and self:IsPublicReportAnnouncementEnabled() then
        AnnouncePublicReportMode()
    end

    return true
end

function Settings:IsPublicReportAnnouncementEnabled()
    local db = GetGlobalDb()
    if not db or type(db.PublicReportAnnouncementEnabled) ~= "boolean" then
        return true
    end

    return db.PublicReportAnnouncementEnabled == true
end

function Settings:SetPublicReportAnnouncementEnabled(enabled)
    local db = GetGlobalDb()
    if not db then
        return false
    end

    db.PublicReportAnnouncementEnabled = enabled == true
    return true
end

function Settings:IsReportOfferEnabled()
    local db = GetGlobalDb()
    return db and db.ReportOfferEnabled == true
end

function Settings:SetReportOfferEnabled(enabled)
    local db = GetGlobalDb()
    if not db then
        return false
    end

    db.ReportOfferEnabled = enabled == true
    if GearPolice.AnnounceCommsState then
        GearPolice:AnnounceCommsState()
    end

    return true
end

function Settings:IsAutoWhisperInRaidOnly()
    local db = GetGlobalDb()
    if not db or type(db.AutoWhisperInRaidOnly) ~= "boolean" then
        return true
    end

    return db.AutoWhisperInRaidOnly == true
end

function Settings:SetAutoWhisperInRaidOnly(enabled)
    local db = GetGlobalDb()
    if not db then
        return false
    end

    db.AutoWhisperInRaidOnly = enabled == true
    return true
end

function Settings:IsAutoWhispersShown()
    local db = GetGlobalDb()
    return not db or db.HideReportOfferWhispers ~= true
end

function Settings:SetAutoWhispersShown(shown)
    local db = GetGlobalDb()
    if not db then
        return false
    end

    db.HideReportOfferWhispers = shown ~= true
    return true
end

function Settings:IsMinimapIconShown()
    local minimapSettings = EnsureMinimapSettings()
    if not minimapSettings then
        return true
    end

    return minimapSettings.hide ~= true
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
            LibDBIcon:Show("GearPolice")
        else
            LibDBIcon:Hide("GearPolice")
        end
    end

    return true
end

function Settings:IsRuleEnabled(ruleId)
    if not CheckDefaults[ruleId] then
        return true
    end

    local enabledChecks = EnsureEnabledChecks()
    if not enabledChecks then
        return CheckDefaults[ruleId] == true
    end

    return enabledChecks[ruleId] == true
end

function Settings:SetRuleEnabled(ruleId, enabled)
    if not CheckDefaults[ruleId] then
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
    local threshold = NormalizeItemLevelThreshold(db and db.ItemLevelThreshold or nil)
    if threshold then
        return threshold
    end

    return GetDefaultItemLevelThreshold()
end

function Settings:SetItemLevelThreshold(value)
    local threshold = NormalizeItemLevelThreshold(value)
    if not threshold then
        return false
    end

    local db = GetGlobalDb()
    if not db then
        return false
    end

    db.ItemLevelThreshold = threshold
    GearPolice.ItemLevelThreshold = threshold
    return true
end

function GearPolice:InitializeSettings()
    return Settings:Initialize()
end
