GearPolice = LibStub("AceAddon-3.0"):NewAddon(
    "GearPolice",
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceTimer-3.0",
    "AceComm-3.0"
)

GearPolice:RegisterChatCommand("gearpolice", "HandleSlashCommands")

function GearPolice:OnInitialize()
    GearPolice:Print("Addon loaded!")

    GearPolice.db = LibStub("AceDB-3.0"):New("GearPoliceDB")

    self:InitializeRuntimeState()
    self.PlayerStore:EnsureStorage()
    self:InitializeSettings()

    -- Initialize DebugEnabled if it's not set
    if type(GearPolice.db.global.DebugEnabled) ~= "boolean" then
        GearPolice.db.global.DebugEnabled = false
    end

    self:InitializeReportOffers()
    self:InitializeComms()
    self:InitializeMinimapIcon()
end

function GearPolice:OnEnable()
    self:RegisterEvent("INSPECT_READY", "OnInspectReady")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "UpdateGroupMembers")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")
    self:RegisterEvent("CHAT_MSG_WHISPER", "OnReportOfferWhisperReceived")
    self:StartComms()
end

function GearPolice:StartGearPolicingOfGroup()
    GearPolice:UpdatePlayerGearInfoWithGroupMembers()
end

function GearPolice:StartGearPolicingOfTarget()
    if not UnitExists("target") or not UnitIsPlayer("target") then
        return
    end

    local targetGuid = UnitGUID("target")
    if targetGuid then
        local targetName, targetRealm = UnitName("target")
        if not targetName or targetName == "Unknown" then
            self:ScheduleManagedTimer(function()
                if UnitGUID("target") == targetGuid then
                    self:StartGearPolicingOfTarget()
                end
            end, 1, targetGuid)
            return
        end

        local targetFullName = targetName
        if type(targetRealm) == "string" and targetRealm ~= "" then
            targetFullName = targetName .. "-" .. targetRealm
        end

        GearPolice:RefreshCurrentRosterSnapshot()
        GearPolice:ResetPlayerGearInfo(targetGuid, targetName, targetFullName)
        GearPolice:AddToScanQueue(targetGuid, true, "target", true)
        GearPolice.UI:UpdateUI()

        GearPolice:ProcessScanQueue()
        GearPolice.UI:UpdateUI()
    end
end

function GearPolice:UpdateGroupMembers()
    GearPolice:UpdatePlayerGearInfoWithGroupMembers()
end

-- Slash command

function GearPolice:PrintSlashCommandHelp()
    GearPolice:Print("Available commands:")
    GearPolice:Print("/gearpolice - Shows this command list.")
    GearPolice:Print("/gearpolice scan - Starts a group scan.")
    GearPolice:Print("/gearpolice showui - Opens the main window.")
    GearPolice:Print("/gearpolice settings - Opens the settings window.")
    GearPolice:Print("/gearpolice target - Scans your current player target.")
    GearPolice:Print("/gearpolice help - Opens the help window.")
    GearPolice:Print("/gearpolice debug - Toggles debug messages.")
end

function GearPolice:HandleSlashCommands(msg, _editbox)
    msg = string.lower((msg or ""):match("^%s*(.-)%s*$"))

    if msg == "" then
        GearPolice:PrintSlashCommandHelp()
    elseif (msg == "scan") then
        GearPolice:StartGearPolicingOfGroup()
    elseif (msg == "target") then
        GearPolice:StartGearPolicingOfTarget()
    elseif (msg == "showui") then
        GearPolice.UI:ShowUI()
    elseif (msg == "settings") then
        GearPolice.UI:ShowSettingsWindow()
    elseif (msg == "help") then
        GearPolice.UI:ShowHelpWindow()
    elseif (msg == "debug") then
        GearPolice.db.global.DebugEnabled = not GearPolice.db.global.DebugEnabled
        GearPolice:Print("Debug mode " .. (GearPolice.db.global.DebugEnabled and "enabled" or "disabled") .. ".")
    else
        GearPolice:PrintSlashCommandHelp()
    end
end
