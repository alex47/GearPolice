GearPolice = LibStub("AceAddon-3.0"):NewAddon("GearPolice", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

GearPolice:RegisterChatCommand("gearpolice", "HandleSlashCommands")

function GearPolice:OnInitialize()
    GearPolice:Print("Addon loaded!")

    GearPolice.db = LibStub("AceDB-3.0"):New("GearPoliceDB")

    self:InitializeRuntimeState()
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

function GearPolice:HandleSlashCommands(msg, _editbox)
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
