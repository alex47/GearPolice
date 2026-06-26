local GearPolice = GearPolice

GearPolice.Comms = GearPolice.Comms or {}

local Comms = GearPolice.Comms

local CommPrefix = "GearPolice"
local ProtocolVersion = "1"
local StateMessageType = "STATE"
local HeartbeatInterval = 30
local PeerExpirySeconds = 90
local RosterAnnounceMinDelay = 0.5
local RosterAnnounceMaxDelay = 2.5
local CoordinatorUnset = false

local function IsGrouped()
    return IsInRaid() or IsInGroup()
end

local function GetCommDistribution()
    if IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end

    return nil
end

local function GetAddonVersion()
    local getter = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if type(getter) ~= "function" then
        return "unknown"
    end

    return getter("GearPolice", "Version") or "unknown"
end

local function IsPlayerGuid(value)
    return type(value) == "string" and string.find(value, "^Player%-") ~= nil
end

local function GetUnitForGuid(playerGuid)
    if GearPolice.Helper and GearPolice.Helper.GetUnitIdOfPlayerGuid then
        return GearPolice.Helper:GetUnitIdOfPlayerGuid(playerGuid)
    end

    return nil
end

local function IsUnitGroupLeader(unitId)
    return unitId
        and type(UnitIsGroupLeader) == "function"
        and UnitIsGroupLeader(unitId)
end

local function IsUnitGroupAssistant(unitId)
    return unitId
        and type(UnitIsGroupAssistant) == "function"
        and UnitIsGroupAssistant(unitId)
end

local function FindRaidRosterIndex(playerGuid)
    local roster = GearPolice.currentRoster
    if roster and roster.sortIndexByGuid and type(roster.sortIndexByGuid[playerGuid]) == "number" then
        return roster.sortIndexByGuid[playerGuid]
    end

    for i = 1, 40 do
        local unitId = "raid" .. i
        if UnitGUID(unitId) == playerGuid then
            return i
        end
    end

    return 999
end

local function GetCoordinatorRosterIndex(playerGuid)
    if IsInRaid() then
        return FindRaidRosterIndex(playerGuid)
    end

    -- Party unit ids are client-relative because each client sees themselves as "player".
    -- GUID tie-break is the stable fallback when leader/assistant rank does not decide.
    return 999
end

local function BuildCandidate(playerGuid)
    local unitId = GetUnitForGuid(playerGuid)

    return {
        playerGuid = playerGuid,
        leaderRank = IsUnitGroupLeader(unitId) and 0 or 1,
        assistantRank = IsUnitGroupAssistant(unitId) and 0 or 1,
        rosterIndex = GetCoordinatorRosterIndex(playerGuid),
        tieBreaker = playerGuid,
    }
end

local function CandidateComesBefore(a, b)
    if not b then
        return true
    end

    if a.leaderRank ~= b.leaderRank then
        return a.leaderRank < b.leaderRank
    end

    if a.assistantRank ~= b.assistantRank then
        return a.assistantRank < b.assistantRank
    end

    if a.rosterIndex ~= b.rosterIndex then
        return a.rosterIndex < b.rosterIndex
    end

    return (a.tieBreaker or "") < (b.tieBreaker or "")
end

local function GetPlayerDisplayName(addon, playerGuid)
    if UnitGUID("player") == playerGuid then
        local playerName = UnitName("player")
        return playerName or "You"
    end

    local playerInfo = addon.PlayerStore and addon.PlayerStore:Get(playerGuid) or nil
    if playerInfo and type(playerInfo.PlayerName) == "string" and playerInfo.PlayerName ~= "" then
        return playerInfo.PlayerName
    end

    local unitId = GetUnitForGuid(playerGuid)
    if unitId then
        local unitName = UnitName(unitId)
        if type(unitName) == "string" and unitName ~= "" and unitName ~= "Unknown" then
            return unitName
        end
    end

    local peer = addon.commsPeers and addon.commsPeers[playerGuid]
    if peer and type(peer.sender) == "string" and peer.sender ~= "" then
        return peer.sender
    end

    return tostring(playerGuid or "none")
end

function Comms.PrunePeers(addon)
    if type(addon.commsPeers) ~= "table" then
        addon.commsPeers = {}
        return
    end

    local currentTime = time()
    for playerGuid, peer in pairs(addon.commsPeers) do
        local lastSeenAt = type(peer) == "table" and peer.lastSeenAt or nil
        if type(lastSeenAt) ~= "number"
            or currentTime - lastSeenAt >= PeerExpirySeconds
            or not GearPolice.Helper:IsPlayerInGroup(playerGuid) then
            addon.commsPeers[playerGuid] = nil
        end
    end
end

function Comms.GetCoordinatorGuid(addon)
    if not IsGrouped() then
        return nil
    end

    Comms.PrunePeers(addon)

    local selectedCandidate
    local localGuid = UnitGUID("player")

    if IsPlayerGuid(localGuid)
        and addon.db
        and addon.db.global
        and addon.db.global.ReportOfferEnabled == true then
        selectedCandidate = BuildCandidate(localGuid)
    end

    for playerGuid, peer in pairs(addon.commsPeers or {}) do
        if peer.reportOffersEnabled == true and GearPolice.Helper:IsPlayerInGroup(playerGuid) then
            local candidate = BuildCandidate(playerGuid)
            if CandidateComesBefore(candidate, selectedCandidate) then
                selectedCandidate = candidate
            end
        end
    end

    return selectedCandidate and selectedCandidate.playerGuid or nil
end

function Comms.UpdateCoordinatorDebug(addon)
    local coordinatorGuid = Comms.GetCoordinatorGuid(addon)
    local previousCoordinatorGuid = addon.commsLastCoordinatorGuid

    if previousCoordinatorGuid == coordinatorGuid then
        return
    end

    addon.commsLastCoordinatorGuid = coordinatorGuid

    if previousCoordinatorGuid == CoordinatorUnset and not coordinatorGuid then
        return
    end

    local coordinatorName = coordinatorGuid and GetPlayerDisplayName(addon, coordinatorGuid) or "none"
    if GearPolice.Debug and GearPolice.Debug.Message then
        GearPolice.Debug:Message("Report offer coordinator: " .. coordinatorName)
    end
end

function Comms.StopHeartbeat(addon)
    if addon.commsHeartbeatTimer then
        addon:CancelTimer(addon.commsHeartbeatTimer)
        addon.commsHeartbeatTimer = nil
    end
end

function Comms.CancelScheduledAnnouncement(addon)
    if addon.commsAnnounceTimer then
        addon:CancelTimer(addon.commsAnnounceTimer)
        addon.commsAnnounceTimer = nil
    end
end

function Comms.ClearPeers(addon)
    addon.commsPeers = {}
end

function Comms.SendState(addon, priority)
    local distribution = GetCommDistribution()
    if not distribution or type(addon.SendCommMessage) ~= "function" then
        return false
    end

    local playerGuid = UnitGUID("player")
    if not IsPlayerGuid(playerGuid) then
        return false
    end

    local reportOffersEnabled = addon.db
        and addon.db.global
        and addon.db.global.ReportOfferEnabled == true
    local message = table.concat({
        StateMessageType,
        ProtocolVersion,
        GetAddonVersion(),
        playerGuid,
        reportOffersEnabled and "1" or "0",
    }, "\t")

    local ok = pcall(
        addon.SendCommMessage,
        addon,
        CommPrefix,
        message,
        distribution,
        nil,
        priority == "BULK" and "BULK" or "NORMAL"
    )

    return ok == true
end

function Comms.StartHeartbeat(addon)
    if addon.commsHeartbeatTimer or not IsGrouped() then
        return
    end

    addon.commsHeartbeatTimer = addon:ScheduleRepeatingTimer(function()
        if not IsGrouped() then
            Comms.RefreshGroupState(addon)
            return
        end

        Comms.PrunePeers(addon)
        Comms.SendState(addon, "BULK")
        Comms.UpdateCoordinatorDebug(addon)
    end, HeartbeatInterval)
end

function Comms.ScheduleRosterAnnouncement(addon)
    if addon.commsAnnounceTimer or not IsGrouped() then
        return
    end

    local delay = RosterAnnounceMinDelay
        + (math.random() * (RosterAnnounceMaxDelay - RosterAnnounceMinDelay))

    addon.commsAnnounceTimer = addon:ScheduleTimer(function()
        addon.commsAnnounceTimer = nil
        if IsGrouped() then
            Comms.SendState(addon, "NORMAL")
            Comms.UpdateCoordinatorDebug(addon)
        end
    end, delay)
end

function Comms.RefreshGroupState(addon, immediate)
    if not IsGrouped() then
        Comms.StopHeartbeat(addon)
        Comms.CancelScheduledAnnouncement(addon)
        Comms.ClearPeers(addon)
        Comms.UpdateCoordinatorDebug(addon)
        return
    end

    Comms.StartHeartbeat(addon)
    Comms.PrunePeers(addon)

    if immediate then
        Comms.CancelScheduledAnnouncement(addon)
        Comms.SendState(addon, "NORMAL")
    else
        Comms.ScheduleRosterAnnouncement(addon)
    end

    Comms.UpdateCoordinatorDebug(addon)
end

function Comms.HandleMessage(addon, prefix, message, distribution, sender)
    if prefix ~= CommPrefix or type(message) ~= "string" or not IsGrouped() then
        return
    end

    if distribution ~= "RAID" and distribution ~= "PARTY" then
        return
    end

    local messageType, protocolVersion, addonVersion, playerGuid, enabledFlag = strsplit("\t", message)
    if messageType ~= StateMessageType
        or protocolVersion ~= ProtocolVersion
        or not IsPlayerGuid(playerGuid)
        or playerGuid == UnitGUID("player")
        or (enabledFlag ~= "1" and enabledFlag ~= "0")
        or not GearPolice.Helper:IsPlayerInGroup(playerGuid) then
        return
    end

    addon.commsPeers[playerGuid] = {
        addonVersion = addonVersion or "unknown",
        reportOffersEnabled = enabledFlag == "1",
        lastSeenAt = time(),
        sender = sender,
    }

    Comms.PrunePeers(addon)
    Comms.UpdateCoordinatorDebug(addon)
end

function Comms.Initialize(addon)
    addon.commsPeers = {}
    addon.commsHeartbeatTimer = nil
    addon.commsAnnounceTimer = nil
    addon.commsLastCoordinatorGuid = CoordinatorUnset

    if type(addon.RegisterComm) == "function" then
        addon:RegisterComm(CommPrefix, "OnGearPoliceCommReceived")
    end
end

function GearPolice:InitializeComms()
    return Comms.Initialize(self)
end

function GearPolice:StartComms()
    return Comms.RefreshGroupState(self, true)
end

function GearPolice:RefreshCommsGroupState()
    return Comms.RefreshGroupState(self, false)
end

function GearPolice:AnnounceCommsState()
    return Comms.RefreshGroupState(self, true)
end

function GearPolice:IsLocalReportOfferCoordinator()
    if not IsGrouped() then
        return true
    end

    if not self.db or not self.db.global or self.db.global.ReportOfferEnabled ~= true then
        return false
    end

    local localGuid = UnitGUID("player")
    if not IsPlayerGuid(localGuid) then
        return true
    end

    local coordinatorGuid = Comms.GetCoordinatorGuid(self)
    if not coordinatorGuid then
        return true
    end

    return coordinatorGuid == localGuid
end

function GearPolice:OnGearPoliceCommReceived(prefix, message, distribution, sender)
    return Comms.HandleMessage(self, prefix, message, distribution, sender)
end
