GearPolice = LibStub("AceAddon-3.0"):NewAddon("GearPolice", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

GearPolice:RegisterChatCommand("gearpolice", "HandleSlashCommands")

GearPolice.scanQueue = {}
GearPolice.queuedScanReasons = {}
GearPolice.currentScan = nil
GearPolice.scanQueueTimer = nil
GearPolice.isScanning = false
GearPolice.activeScanGuids = {}
GearPolice.activeTimers = {}
GearPolice.activePlayerTimers = {}
GearPolice.currentRoster = nil
GearPolice.wasGrouped = false

function GearPolice:OnInitialize()
    GearPolice:Print("Addon loaded!")

    GearPolice.db = LibStub("AceDB-3.0"):New("GearPoliceDB")

    self.activeScanGuids = {}
    self.activeTimers = {}
    self.activePlayerTimers = {}
    self.queuedScanReasons = {}
    self.currentScan = nil
    self.scanQueueTimer = nil
    self.isScanning = false
    self.wasGrouped = IsInRaid() or IsInGroup()
    self:ResetRosterSnapshot()

    self.PlayerStore:EnsureStorage()

    if GearPolice.db.global.ReportMode ~= "whisper"
        and GearPolice.db.global.ReportMode ~= "public"
        and GearPolice.db.global.ReportMode ~= "debug" then
        GearPolice.db.global.ReportMode = "whisper"
    end

    -- Initialize DebugEnabled if it's not set
    if type(GearPolice.db.global.DebugEnabled) ~= "boolean" then
        GearPolice.db.global.DebugEnabled = false
    end
end

function GearPolice:OnEnable()
    self:RegisterEvent("INSPECT_READY", "OnInspectReady")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "UpdateGroupMembers")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")
end

function GearPolice:ClearScheduledWorkForPlayer(playerGuid)
    if not playerGuid then
        return
    end

    self:CancelManagedTimersForPlayer(playerGuid)
    self:RemoveFromScanQueue(playerGuid)
    self:ClearCurrentScanForPlayer(playerGuid)
end

function GearPolice:RemovePlayerFromTracking(playerGuid)
    if not playerGuid or not self.db or not self.db.global then
        return
    end

    self:ClearScheduledWorkForPlayer(playerGuid)

    self.PlayerStore:Remove(playerGuid)

    self:RemoveGuidFromCurrentRoster(playerGuid)
end

function GearPolice:StopAllScans()
    self:CancelAllManagedTimers()

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end

    self.scanQueue = {}
    self.queuedScanReasons = {}
    self.currentScan = nil
    self.activeScanGuids = {}
    self.isScanning = false
    self.scanQueueTimer = nil
    self:ResetRosterSnapshot()

    self.PlayerStore:MarkAllScansCancelled()
end

function GearPolice:ClearAllTrackedPlayers()
    self:StopAllScans()

    self.PlayerStore:ClearAll()

    self:ResetRosterSnapshot()
    self.UI:UpdateUI()
end

function GearPolice:ClearTrackedPlayersForRosterTransition()
    self:StopAllScans()

    self.PlayerStore:ClearAll()

    self:ResetRosterSnapshot()
end

function GearPolice:StartGearPolicingOfGroup()
    GearPolice:UpdatePlayerGearInfoWithGroupMembers()
end

function GearPolice:StartGearPolicingOfTarget()
    local targetGuid = UnitGUID("target")
    if targetGuid then
        local targetName = UnitName("target")
        if not targetName or targetName == "Unknown" then
            self:ScheduleManagedTimer(function()
                if UnitGUID("target") == targetGuid then
                    self:StartGearPolicingOfTarget()
                end
            end, 1, targetGuid)
            return
        end

        GearPolice:RefreshCurrentRosterSnapshot()
        GearPolice:ResetPlayerGearInfo(targetGuid, targetName)
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

function GearPolice:HandleSlashCommands(msg, editbox)
    if (msg == "target") then
        GearPolice:StartGearPolicingOfTarget()
    elseif (msg == "showui") then
        GearPolice.UI:ShowUI()
    elseif (msg == "debug") then
        GearPolice.db.global.DebugEnabled = not GearPolice.db.global.DebugEnabled
        GearPolice:Print("Debug mode " .. (GearPolice.db.global.DebugEnabled and "enabled" or "disabled") .. ".")
    else
        -- Start scanning group when no argument is provided
        GearPolice:StartGearPolicingOfGroup()
    end
end
