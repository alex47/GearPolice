local AddonName = "GearPolice"

GearPolice = LibStub("AceAddon-3.0"):NewAddon(
    AddonName,
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceTimer-3.0",
    "AceComm-3.0"
)

GearPolice.AddonName = AddonName

GearPolice:RegisterChatCommand("gearpolice", "HandleSlashCommands")

local SlashCommands = {
    {
        keyword = "",
        syntax = "/gearpolice",
        description = "Shows this command list.",
    },
    {
        keyword = "scan",
        syntax = "/gearpolice scan",
        description = "Clears the current list and rescans your group.",
        handler = function(addon)
            addon:RescanGroup()
        end,
    },
    {
        keyword = "showui",
        syntax = "/gearpolice showui",
        description = "Opens the main window.",
        handler = function(addon)
            addon.UI:ShowUI()
        end,
    },
    {
        keyword = "settings",
        syntax = "/gearpolice settings",
        description = "Opens the settings page.",
        handler = function(addon)
            addon.UI:OpenAceConfigSettings()
        end,
    },
    {
        keyword = "target",
        syntax = "/gearpolice target",
        description = "Scans your current player target.",
        handler = function(addon)
            addon:StartGearPolicingOfTarget()
        end,
    },
    {
        keyword = "help",
        syntax = "/gearpolice help",
        description = "Opens the help window.",
        handler = function(addon)
            addon.UI:ShowHelpWindow()
        end,
    },
    {
        keyword = "debug",
        syntax = "/gearpolice debug",
        description = "Toggles debug messages.",
        handler = function(addon)
            local enabled = not addon.Settings:IsDebugEnabled()
            addon.Settings:SetDebugEnabled(enabled)
            addon:Print("Debug mode " .. (enabled and "enabled" or "disabled") .. ".")
        end,
    },
}

function GearPolice:OnInitialize()
    GearPolice:Print("Addon loaded!")

    GearPolice.db = LibStub("AceDB-3.0"):New("GearPoliceDB")

    self:InitializeRuntimeState()
    self.PlayerStore:EnsureStorage()
    for _, playerInfo in pairs(self.PlayerStore:GetAll() or {}) do
        self.Problems.NormalizeStoredPlayer(playerInfo)
    end
    self:InitializeSettings()
    self.UI:RegisterAceConfigSettings()

    self:InitializeReportOffers()
    self:InitializePublicScanAnnouncements()
    self:InitializeComms()
    self:InitializeMinimapIcon()
end

function GearPolice:OnEnable()
    self:RegisterEvent("INSPECT_READY", "OnInspectReady")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "UpdateGroupMembers")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStarted")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnPlayerTargetChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("CHAT_MSG_WHISPER", "OnReportOfferWhisperReceived")
    self:UpdatePlayerGearInfoWithGroupMembers()
    self:StartComms()
end

function GearPolice:StartGearPolicingOfGroup()
    GearPolice:UpdatePlayerGearInfoWithGroupMembers()
end

function GearPolice:RescanGroup()
    GearPolice:ClearAllTrackedPlayers()
    GearPolice:StartGearPolicingOfGroup()
end

function GearPolice:StartGearPolicingOfTarget()
    if not UnitExists("target") or not UnitIsPlayer("target") then
        return
    end

    local targetGuid = UnitGUID("target")
    if targetGuid then
        local targetName, targetRealm = UnitName("target")
        if not self.Players.IsKnownName(targetName) then
            self:ScheduleManagedTimer(function()
                if UnitGUID("target") == targetGuid then
                    self:StartGearPolicingOfTarget()
                end
            end, 1, targetGuid)
            return
        end

        local targetFullName = self.Players.BuildFullName(targetName, targetRealm)

        GearPolice:RefreshCurrentRosterSnapshot()
        GearPolice:ResetPlayerGearInfo(targetGuid, targetName, targetFullName)
        GearPolice:AddToScanQueue(targetGuid, true, self.Constants.ScanReason.Target, true)
        GearPolice.UI:UpdateUI()

        GearPolice:ProcessScanQueue()
        GearPolice.UI:UpdateUI()
    end
end

function GearPolice:UpdateGroupMembers()
    GearPolice:UpdatePlayerGearInfoWithGroupMembers()
end

function GearPolice:OnPlayerEnteringWorld()
    if not self.Settings:IsAutomaticPublicMessagingAllowedInCurrentInstance() then
        if self.ClearPendingReportOffers then
            self:ClearPendingReportOffers()
        end

        if self.ClearPendingPublicScanAnnouncements then
            self:ClearPendingPublicScanAnnouncements()
        end
    end

    if self.AnnounceCommsState then
        self:AnnounceCommsState()
    end
end

function GearPolice:PrintSlashCommandHelp()
    self:Print("Available commands:")
    for _, command in ipairs(SlashCommands) do
        self:Print(command.syntax .. " - " .. command.description)
    end
end

function GearPolice:GetSlashCommands()
    return SlashCommands
end

function GearPolice:GetSlashCommandHelpText(separator)
    local lines = {}
    for _, command in ipairs(SlashCommands) do
        table.insert(lines, command.syntax .. " " .. command.description)
    end

    return table.concat(lines, separator or "\n")
end

function GearPolice:HandleSlashCommands(msg, _editbox)
    msg = string.lower((msg or ""):match("^%s*(.-)%s*$"))

    for _, command in ipairs(SlashCommands) do
        if command.keyword == msg then
            if command.handler then
                command.handler(self)
            else
                self:PrintSlashCommandHelp()
            end
            return
        end
    end

    self:PrintSlashCommandHelp()
end
