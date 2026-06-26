local GearPolice = GearPolice

GearPolice.Comms = GearPolice.Comms or {}

local CommPrefix = "GearPolice"
local ProtocolVersion = "1"
local StateMessageType = "STATE"
local HeartbeatInterval = 30
local PeerExpirySeconds = 90
local RosterAnnounceMinDelay = 0.5
local RosterAnnounceMaxDelay = 2.5
local CoordinationWarmupSeconds = 3
local CoordinatorUnset = false

local function IsGrouped()
    return IsInRaid() or IsInGroup()
end

local function IsKnownPlayerName(playerName)
    return type(playerName) == "string" and playerName ~= "" and playerName ~= "Unknown"
end

local function NormalizePlayerName(playerName)
    if not IsKnownPlayerName(playerName) then
        return nil
    end

    return string.lower(playerName)
end

local function BuildFullPlayerName(playerName, playerRealm)
    if not IsKnownPlayerName(playerName) then
        return nil
    end

    if type(playerRealm) == "string" and playerRealm ~= "" then
        return playerName .. "-" .. playerRealm
    end

    return playerName
end

local function GetUnitFullPlayerName(unitId)
    if not unitId or not UnitExists(unitId) then
        return nil
    end

    local playerName, playerRealm = UnitName(unitId)
    if unitId == "player" and (not playerRealm or playerRealm == "") and type(GetRealmName) == "function" then
        playerRealm = GetRealmName()
    end

    return BuildFullPlayerName(playerName, playerRealm)
end

local function GetLocalPlayerName()
    return GetUnitFullPlayerName("player")
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

local function GetStoredPlayerName(addon, playerGuid)
    local playerInfo = addon.PlayerStore and addon.PlayerStore:Get(playerGuid) or nil
    if not playerInfo then
        return nil
    end

    if IsKnownPlayerName(playerInfo.PlayerFullName) then
        return playerInfo.PlayerFullName
    end

    if IsKnownPlayerName(playerInfo.PlayerName) then
        return playerInfo.PlayerName
    end

    return nil
end

local function GetCandidateName(addon, playerGuid, peer)
    if UnitGUID("player") == playerGuid then
        return GetLocalPlayerName()
    end

    if peer and IsKnownPlayerName(peer.playerName) then
        return peer.playerName
    end

    local storedName = GetStoredPlayerName(addon, playerGuid)
    if storedName then
        return storedName
    end

    local unitId = GetUnitForGuid(playerGuid)
    local unitName = GetUnitFullPlayerName(unitId)
    if unitName then
        return unitName
    end

    if peer and IsKnownPlayerName(peer.sender) then
        return peer.sender
    end

    return tostring(playerGuid or "")
end

local function BuildCandidate(addon, playerGuid, peer)
    local unitId = GetUnitForGuid(playerGuid)

    return {
        playerGuid = playerGuid,
        leaderRank = IsUnitGroupLeader(unitId) and 0 or 1,
        assistantRank = IsUnitGroupAssistant(unitId) and 0 or 1,
        rosterIndex = IsInRaid() and FindRaidRosterIndex(playerGuid) or 999,
        playerName = NormalizePlayerName(GetCandidateName(addon, playerGuid, peer)) or tostring(playerGuid or ""),
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

    if IsInRaid() and a.rosterIndex ~= b.rosterIndex then
        return a.rosterIndex < b.rosterIndex
    end

    if not IsInRaid() and a.playerName ~= b.playerName then
        return a.playerName < b.playerName
    end

    return (a.tieBreaker or "") < (b.tieBreaker or "")
end

local function GetPlayerDisplayName(addon, playerGuid)
    if UnitGUID("player") == playerGuid then
        local playerName = UnitName("player")
        return playerName or "You"
    end

    local candidateName = GetCandidateName(addon, playerGuid, addon.commsPeers and addon.commsPeers[playerGuid])
    if IsKnownPlayerName(candidateName) then
        return candidateName
    end

    return tostring(playerGuid or "none")
end

local function PrunePeers(addon)
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

local function GetCoordinatorGuid(addon)
    if not IsGrouped() then
        return nil
    end

    PrunePeers(addon)

    local selectedCandidate
    local localGuid = UnitGUID("player")

    if IsPlayerGuid(localGuid)
        and addon.db
        and addon.db.global
        and addon.db.global.ReportOfferEnabled == true then
        selectedCandidate = BuildCandidate(addon, localGuid)
    end

    for playerGuid, peer in pairs(addon.commsPeers or {}) do
        if peer.reportOffersEnabled == true and GearPolice.Helper:IsPlayerInGroup(playerGuid) then
            local candidate = BuildCandidate(addon, playerGuid, peer)
            if CandidateComesBefore(candidate, selectedCandidate) then
                selectedCandidate = candidate
            end
        end
    end

    return selectedCandidate and selectedCandidate.playerGuid or nil
end

local function UpdateCoordinatorDebug(addon)
    local coordinatorGuid = GetCoordinatorGuid(addon)
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

local function StopHeartbeat(addon)
    if addon.commsHeartbeatTimer then
        addon:CancelTimer(addon.commsHeartbeatTimer)
        addon.commsHeartbeatTimer = nil
    end
end

local function CancelScheduledAnnouncement(addon)
    if addon.commsAnnounceTimer then
        addon:CancelTimer(addon.commsAnnounceTimer)
        addon.commsAnnounceTimer = nil
    end
end

local function CancelCoordinationWarmup(addon)
    if addon.commsWarmupTimer then
        addon:CancelTimer(addon.commsWarmupTimer)
        addon.commsWarmupTimer = nil
    end

    addon.commsWarmupActive = false
end

local function FinishCoordinationWarmup(addon)
    addon.commsWarmupTimer = nil
    addon.commsWarmupActive = false

    UpdateCoordinatorDebug(addon)

    if addon.SendPendingReportOffersAfterCoordination then
        addon:SendPendingReportOffersAfterCoordination()
    end
end

local function StartCoordinationWarmup(addon)
    if not IsGrouped() then
        CancelCoordinationWarmup(addon)
        return
    end

    if addon.commsWarmupTimer then
        addon:CancelTimer(addon.commsWarmupTimer)
    end

    addon.commsWarmupActive = true
    addon.commsWarmupTimer = addon:ScheduleTimer(function()
        FinishCoordinationWarmup(addon)
    end, CoordinationWarmupSeconds)
end

local function ClearPeers(addon)
    addon.commsPeers = {}
end

local function BuildStateMessage(addon)
    local playerGuid = UnitGUID("player")
    if not IsPlayerGuid(playerGuid) then
        return nil
    end

    local reportOffersEnabled = addon.db
        and addon.db.global
        and addon.db.global.ReportOfferEnabled == true

    return table.concat({
        StateMessageType,
        ProtocolVersion,
        GetAddonVersion(),
        playerGuid,
        reportOffersEnabled and "1" or "0",
        GetLocalPlayerName() or "",
    }, "\t")
end

local function SendState(addon, priority)
    local distribution = GetCommDistribution()
    if not distribution or type(addon.SendCommMessage) ~= "function" then
        return false
    end

    local message = BuildStateMessage(addon)
    if not message then
        return false
    end

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

local function StartHeartbeat(addon)
    if addon.commsHeartbeatTimer or not IsGrouped() then
        return
    end

    addon.commsHeartbeatTimer = addon:ScheduleRepeatingTimer(function()
        if not IsGrouped() then
            GearPolice:RefreshCommsGroupState()
            return
        end

        PrunePeers(addon)
        SendState(addon, "BULK")
        UpdateCoordinatorDebug(addon)
    end, HeartbeatInterval)
end

local function ScheduleRosterAnnouncement(addon)
    if addon.commsAnnounceTimer or not IsGrouped() then
        return
    end

    local delay = RosterAnnounceMinDelay
        + (math.random() * (RosterAnnounceMaxDelay - RosterAnnounceMinDelay))

    addon.commsAnnounceTimer = addon:ScheduleTimer(function()
        addon.commsAnnounceTimer = nil
        if IsGrouped() then
            SendState(addon, "NORMAL")
            UpdateCoordinatorDebug(addon)
        end
    end, delay)
end

local function RefreshGroupState(addon, immediate, startWarmup)
    if not IsGrouped() then
        StopHeartbeat(addon)
        CancelScheduledAnnouncement(addon)
        CancelCoordinationWarmup(addon)
        ClearPeers(addon)
        UpdateCoordinatorDebug(addon)
        return
    end

    StartHeartbeat(addon)
    PrunePeers(addon)

    if immediate then
        CancelScheduledAnnouncement(addon)
        SendState(addon, "NORMAL")
    else
        ScheduleRosterAnnouncement(addon)
    end

    if startWarmup then
        StartCoordinationWarmup(addon)
    end

    UpdateCoordinatorDebug(addon)
end

local function HandleMessage(addon, prefix, message, distribution, sender)
    if prefix ~= CommPrefix or type(message) ~= "string" or not IsGrouped() then
        return
    end

    if distribution ~= "RAID" and distribution ~= "PARTY" then
        return
    end

    local messageType, protocolVersion, addonVersion, playerGuid, enabledFlag, playerName =
        strsplit("\t", message)

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
        playerName = IsKnownPlayerName(playerName) and playerName or nil,
    }

    PrunePeers(addon)
    UpdateCoordinatorDebug(addon)
end

function GearPolice:InitializeComms()
    self.commsPeers = {}
    self.commsHeartbeatTimer = nil
    self.commsAnnounceTimer = nil
    self.commsWarmupTimer = nil
    self.commsWarmupActive = false
    self.commsLastCoordinatorGuid = CoordinatorUnset

    if type(self.RegisterComm) == "function" then
        self:RegisterComm(CommPrefix, "OnGearPoliceCommReceived")
    end
end

function GearPolice:StartComms()
    return RefreshGroupState(self, true, true)
end

function GearPolice:RefreshCommsGroupState()
    return RefreshGroupState(self, false, true)
end

function GearPolice:AnnounceCommsState()
    return RefreshGroupState(self, true, true)
end

function GearPolice:IsReportOfferCoordinationWarmupActive()
    return self.commsWarmupActive == true
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

    local coordinatorGuid = GetCoordinatorGuid(self)
    if not coordinatorGuid then
        return true
    end

    return coordinatorGuid == localGuid
end

function GearPolice:OnGearPoliceCommReceived(prefix, message, distribution, sender)
    return HandleMessage(self, prefix, message, distribution, sender)
end
