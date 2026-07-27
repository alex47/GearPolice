local GearPolice = GearPolice

GearPolice.Comms = GearPolice.Comms or {}

local CommPrefix = GearPolice.AddonName
local ProtocolVersion = "1"
local StateMessageType = "STATE"
local PublicAnnouncementMessageType = "PUBLIC_ANNOUNCED"
local HeartbeatInterval = 30
local PeerExpirySeconds = 90
local RosterAnnounceMinDelay = 0.5
local RosterAnnounceMaxDelay = 2.5
local CoordinationWarmupSeconds = 3
local CoordinatorUnset = false

local function IsGrouped()
    return IsInRaid() or IsInGroup()
end

local function GetLocalPlayerName()
    return GearPolice.Players.GetUnitFullName("player")
end

local function GetCommDistribution()
    return GearPolice.Units.GetGroupChatType()
end

local function IsLocalReportOfferEligible(addon)
    return addon.Settings
        and addon.Settings:IsReportOfferEnabled()
        and addon.Settings:IsAutoWhisperEnabledForCurrentGroup()
end

local function IsLocalPublicAnnouncementEligible(addon)
    return addon.Settings
        and addon.Settings:IsPublicScanAnnouncementEnabledForCurrentGroup()
end

local function GetAddonVersion()
    local getter = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if type(getter) ~= "function" then
        return "unknown"
    end

    return getter(GearPolice.AddonName, "Version") or "unknown"
end

local function GetUnitForGuid(playerGuid)
    return GearPolice.Units.GetUnitIdOfPlayerGuid(playerGuid)
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

    return GearPolice.Players.GetStoredFullName(playerInfo)
end

local function GetCandidateName(addon, playerGuid, peer)
    if UnitGUID("player") == playerGuid then
        return GetLocalPlayerName()
    end

    local unitId = GetUnitForGuid(playerGuid)
    local unitName = GearPolice.Players.GetUnitFullName(unitId)
    if unitName then
        return unitName
    end

    local storedName = GetStoredPlayerName(addon, playerGuid)
    if storedName then
        return storedName
    end

    if peer and GearPolice.Players.IsKnownName(peer.playerName) then
        return peer.playerName
    end

    if peer and GearPolice.Players.IsKnownName(peer.sender) then
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
        playerName = GearPolice.Players.NormalizeFullName(GetCandidateName(addon, playerGuid, peer))
            or tostring(playerGuid or ""),
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
    if GearPolice.Players.IsKnownName(candidateName) then
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
            or not GearPolice.Units.IsPlayerInGroup(playerGuid) then
            addon.commsPeers[playerGuid] = nil
        end
    end
end

local function GetCoordinatorGuid(addon, localEligibility, peerEligibilityField)
    if not IsGrouped() then
        return nil
    end

    PrunePeers(addon)

    local selectedCandidate
    local localGuid = UnitGUID("player")

    if GearPolice.Players.IsPlayerGuid(localGuid) and localEligibility(addon) then
        selectedCandidate = BuildCandidate(addon, localGuid)
    end

    for playerGuid, peer in pairs(addon.commsPeers or {}) do
        if peer[peerEligibilityField] == true and GearPolice.Units.IsPlayerInGroup(playerGuid) then
            local candidate = BuildCandidate(addon, playerGuid, peer)
            if CandidateComesBefore(candidate, selectedCandidate) then
                selectedCandidate = candidate
            end
        end
    end

    return selectedCandidate and selectedCandidate.playerGuid or nil
end

local function GetReportOfferCoordinatorGuid(addon)
    return GetCoordinatorGuid(addon, IsLocalReportOfferEligible, "reportOffersEligible")
end

local function GetPublicAnnouncementCoordinatorGuid(addon)
    return GetCoordinatorGuid(
        addon,
        IsLocalPublicAnnouncementEligible,
        "publicAnnouncementsEligible"
    )
end

local function UpdateCoordinatorDebugValue(addon, coordinatorGuid, stateField, messageLabel)
    local previousCoordinatorGuid = addon[stateField]

    if previousCoordinatorGuid == coordinatorGuid then
        return
    end

    addon[stateField] = coordinatorGuid

    if previousCoordinatorGuid == CoordinatorUnset and not coordinatorGuid then
        return
    end

    local coordinatorName = coordinatorGuid and GetPlayerDisplayName(addon, coordinatorGuid) or "none"
    if GearPolice.Debug and GearPolice.Debug.Message then
        GearPolice.Debug:Message(messageLabel .. coordinatorName)
    end
end

local function UpdateCoordinatorDebug(addon)
    UpdateCoordinatorDebugValue(
        addon,
        GetReportOfferCoordinatorGuid(addon),
        "commsLastCoordinatorGuid",
        "Report offer coordinator: "
    )
    UpdateCoordinatorDebugValue(
        addon,
        GetPublicAnnouncementCoordinatorGuid(addon),
        "commsLastPublicAnnouncementCoordinatorGuid",
        "Automatic announcement coordinator: "
    )
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
    if addon.SendPendingPublicScanAnnouncementsAfterCoordination then
        addon:SendPendingPublicScanAnnouncementsAfterCoordination()
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
    if not GearPolice.Players.IsPlayerGuid(playerGuid) then
        return nil
    end

    local reportOffersEligible = IsLocalReportOfferEligible(addon)
    local publicAnnouncementsEligible = IsLocalPublicAnnouncementEligible(addon)

    return table.concat({
        StateMessageType,
        ProtocolVersion,
        GetAddonVersion(),
        playerGuid,
        reportOffersEligible and "1" or "0",
        GetLocalPlayerName() or "",
        publicAnnouncementsEligible and "1" or "0",
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

local function SendPublicAnnouncementState(addon, playerGuid)
    local distribution = GetCommDistribution()
    local localGuid = UnitGUID("player")
    if not distribution
        or not GearPolice.Players.IsPlayerGuid(localGuid)
        or not GearPolice.Players.IsPlayerGuid(playerGuid)
        or type(addon.SendCommMessage) ~= "function" then
        return false
    end

    local message = table.concat({
        PublicAnnouncementMessageType,
        ProtocolVersion,
        localGuid,
        playerGuid,
    }, "\t")

    local ok = pcall(
        addon.SendCommMessage,
        addon,
        CommPrefix,
        message,
        distribution,
        nil,
        "NORMAL"
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

local function GetSenderRosterSnapshot(addon)
    if addon.BuildGroupRosterSnapshot then
        return addon:BuildGroupRosterSnapshot()
    end

    return addon.currentRoster
end

local function ResolveCommSender(addon, sender)
    local normalizedSender = GearPolice.Players.NormalizeFullName(sender)
    if not normalizedSender then
        return nil, nil
    end

    local snapshot = GetSenderRosterSnapshot(addon)
    if not snapshot or not snapshot.orderedGuids then
        return nil, nil
    end

    local exactGuid
    local exactName
    local shortGuid
    local shortName
    local shortMatchCount = 0
    local normalizedSenderShort = GearPolice.Players.NormalizeShortName(sender)

    for _, rosterGuid in ipairs(snapshot.orderedGuids) do
        local unitId = snapshot.unitIdByGuid and snapshot.unitIdByGuid[rosterGuid]
        if unitId and UnitGUID(unitId) == rosterGuid then
            local unitFullName = GearPolice.Players.GetUnitFullName(unitId)
            local normalizedUnitFullName = GearPolice.Players.NormalizeFullName(unitFullName)
            if normalizedUnitFullName == normalizedSender then
                if exactGuid then
                    return nil, nil
                end

                exactGuid = rosterGuid
                exactName = unitFullName
            end

            local unitName = UnitName(unitId)
            if GearPolice.Players.NormalizeShortName(unitName) == normalizedSenderShort then
                shortGuid = rosterGuid
                shortName = unitFullName or unitName
                shortMatchCount = shortMatchCount + 1
            end
        end
    end

    if exactGuid then
        return exactGuid, exactName
    end

    if shortMatchCount == 1 then
        return shortGuid, shortName
    end

    return nil, nil
end

local function HandleStateMessage(addon, message, sender, senderGuid, senderFullName)
    local messageType, protocolVersion, addonVersion, playerGuid, eligibilityFlag,
        _, publicAnnouncementEligibilityFlag = strsplit("\t", message)

    if publicAnnouncementEligibilityFlag == nil or publicAnnouncementEligibilityFlag == "" then
        publicAnnouncementEligibilityFlag = "0"
    end

    if messageType ~= StateMessageType
        or protocolVersion ~= ProtocolVersion
        or not GearPolice.Players.IsPlayerGuid(playerGuid)
        or playerGuid == UnitGUID("player")
        or (eligibilityFlag ~= "1" and eligibilityFlag ~= "0")
        or (publicAnnouncementEligibilityFlag ~= "1"
            and publicAnnouncementEligibilityFlag ~= "0")
        or senderGuid ~= playerGuid then
        return
    end

    addon.commsPeers[playerGuid] = {
        addonVersion = addonVersion or "unknown",
        reportOffersEligible = eligibilityFlag == "1",
        publicAnnouncementsEligible = publicAnnouncementEligibilityFlag == "1",
        lastSeenAt = time(),
        sender = sender,
        playerName = senderFullName,
    }

    PrunePeers(addon)
    UpdateCoordinatorDebug(addon)
end

local function HandlePublicAnnouncementMessage(addon, message, senderGuid)
    local messageType, protocolVersion, announcingGuid, playerGuid = strsplit("\t", message)
    if messageType ~= PublicAnnouncementMessageType
        or protocolVersion ~= ProtocolVersion
        or not GearPolice.Players.IsPlayerGuid(announcingGuid)
        or not GearPolice.Players.IsPlayerGuid(playerGuid)
        or senderGuid ~= announcingGuid
        or not GearPolice.Units.IsPlayerInGroup(playerGuid) then
        return
    end

    local peer = addon.commsPeers and addon.commsPeers[announcingGuid]
    if not peer
        or peer.publicAnnouncementsEligible ~= true
        or GetPublicAnnouncementCoordinatorGuid(addon) ~= announcingGuid then
        return
    end

    if addon.RecordPublicScanAnnouncement then
        addon:RecordPublicScanAnnouncement(playerGuid)
    end
end

local function HandleMessage(addon, prefix, message, distribution, sender)
    if prefix ~= CommPrefix or type(message) ~= "string" or not IsGrouped() then
        return
    end

    if distribution ~= GetCommDistribution() then
        return
    end

    local senderGuid, senderFullName = ResolveCommSender(addon, sender)
    if not senderGuid then
        return
    end

    local messageType = strsplit("\t", message)
    if messageType == StateMessageType then
        HandleStateMessage(addon, message, sender, senderGuid, senderFullName)
    elseif messageType == PublicAnnouncementMessageType then
        HandlePublicAnnouncementMessage(addon, message, senderGuid)
    end
end

function GearPolice:InitializeComms()
    self.commsPeers = {}
    self.commsHeartbeatTimer = nil
    self.commsAnnounceTimer = nil
    self.commsWarmupTimer = nil
    self.commsWarmupActive = false
    self.commsLastCoordinatorGuid = CoordinatorUnset
    self.commsLastPublicAnnouncementCoordinatorGuid = CoordinatorUnset

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

function GearPolice:IsCommsCoordinationWarmupActive()
    return self.commsWarmupActive == true
end

function GearPolice:IsLocalReportOfferCoordinator()
    if not IsGrouped() then
        return true
    end

    if not IsLocalReportOfferEligible(self) then
        return false
    end

    local localGuid = UnitGUID("player")
    if not GearPolice.Players.IsPlayerGuid(localGuid) then
        return true
    end

    local coordinatorGuid = GetReportOfferCoordinatorGuid(self)
    if not coordinatorGuid then
        return true
    end

    return coordinatorGuid == localGuid
end

function GearPolice:IsLocalPublicAnnouncementCoordinator()
    if not IsGrouped() then
        return false
    end

    if not IsLocalPublicAnnouncementEligible(self) then
        return false
    end

    local localGuid = UnitGUID("player")
    if not GearPolice.Players.IsPlayerGuid(localGuid) then
        return true
    end

    local coordinatorGuid = GetPublicAnnouncementCoordinatorGuid(self)
    if not coordinatorGuid then
        return true
    end

    return coordinatorGuid == localGuid
end

function GearPolice:AnnouncePublicScanSummarySent(playerGuid)
    return SendPublicAnnouncementState(self, playerGuid)
end

function GearPolice:OnGearPoliceCommReceived(prefix, message, distribution, sender)
    return HandleMessage(self, prefix, message, distribution, sender)
end
