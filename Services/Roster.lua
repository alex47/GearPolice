local GearPolice = GearPolice

GearPolice.Roster = GearPolice.Roster or {}

local Roster = GearPolice.Roster
local Constants = GearPolice.Constants
local Players = GearPolice.Players
local ScanReason = GearPolice.Constants.ScanReason
local ScanStatus = GearPolice.Constants.ScanStatus

function Roster.CreateEmptySnapshot(groupType)
    return {
        presentGuids = {},
        unitIdByGuid = {},
        sortIndexByGuid = {},
        orderedGuids = {},
        groupType = groupType,
    }
end

function Roster.ResetSnapshot(addon)
    addon.currentRoster = Roster.CreateEmptySnapshot(nil)
end

function Roster.BuildSnapshot(_addon)
    local groupType, maxMembers
    if IsInRaid() then
        groupType = "raid"
        maxMembers = 40
    elseif IsInGroup() then
        groupType = "party"
        maxMembers = 4
    else
        return Roster.CreateEmptySnapshot(nil)
    end

    local snapshot = Roster.CreateEmptySnapshot(groupType)

    local function AddUnitToSnapshot(unitId, sortIndex)
        if not UnitExists(unitId) then
            return
        end

        local playerGuid = UnitGUID(unitId)
        if playerGuid and not snapshot.presentGuids[playerGuid] then
            snapshot.presentGuids[playerGuid] = true
            snapshot.unitIdByGuid[playerGuid] = unitId
            snapshot.sortIndexByGuid[playerGuid] = sortIndex
            table.insert(snapshot.orderedGuids, playerGuid)
        end
    end

    if groupType == "party" then
        AddUnitToSnapshot("player", 0)
    end

    for i = 1, maxMembers do
        AddUnitToSnapshot(groupType .. i, i)
    end

    return snapshot
end

function Roster.ApplyMetadata(playerInfo, playerGuid, unitId, sortIndex, groupType)
    if not playerInfo then
        return
    end

    playerInfo.IsRosterTracked = true
    playerInfo.CurrentUnitId = unitId
    playerInfo.RosterSortIndex = sortIndex
    playerInfo.RosterGroupType = groupType
    playerInfo.PlayerGuid = playerGuid or playerInfo.PlayerGuid
end

function Roster.ClearMetadata(playerInfo)
    if not playerInfo then
        return
    end

    playerInfo.IsRosterTracked = false
    playerInfo.CurrentUnitId = nil
    playerInfo.RosterSortIndex = nil
    playerInfo.RosterGroupType = nil
end

function Roster.RefreshSnapshot(addon)
    if IsInRaid() or IsInGroup() then
        addon.currentRoster = Roster.BuildSnapshot(addon)
    else
        Roster.ResetSnapshot(addon)
    end

    return addon.currentRoster
end

function Roster.ApplyCurrentMetadata(addon, playerGuid, playerInfo)
    local roster = addon.currentRoster
    if roster and roster.presentGuids and roster.presentGuids[playerGuid] then
        Roster.ApplyMetadata(
            playerInfo,
            playerGuid,
            roster.unitIdByGuid[playerGuid],
            roster.sortIndexByGuid[playerGuid],
            roster.groupType
        )
    else
        Roster.ClearMetadata(playerInfo)
    end
end

function Roster.RemoveGuidFromCurrent(addon, playerGuid)
    local roster = addon.currentRoster
    if not playerGuid or not roster then
        return
    end

    if roster.presentGuids then
        roster.presentGuids[playerGuid] = nil
    end
    if roster.unitIdByGuid then
        roster.unitIdByGuid[playerGuid] = nil
    end
    if roster.sortIndexByGuid then
        roster.sortIndexByGuid[playerGuid] = nil
    end
    if roster.orderedGuids then
        for i = #roster.orderedGuids, 1, -1 do
            if roster.orderedGuids[i] == playerGuid then
                table.remove(roster.orderedGuids, i)
            end
        end
    end
end

function Roster.Reconcile(addon, snapshot)
    if not snapshot or not snapshot.groupType then
        addon:ClearAllTrackedPlayers()
        return
    end

    local playerGearInfo = addon.PlayerStore:GetAll()
    local removeGuids = {}

    for playerGuid, playerInfo in pairs(playerGearInfo) do
        if playerInfo.IsRosterTracked ~= false and not snapshot.presentGuids[playerGuid] then
            table.insert(removeGuids, playerGuid)
        end
    end

    for _, playerGuid in ipairs(removeGuids) do
        addon:RemovePlayerFromTracking(playerGuid)
    end

    addon.currentRoster = snapshot

    for _, playerGuid in ipairs(snapshot.orderedGuids) do
        local unitId = snapshot.unitIdByGuid[playerGuid]
        Roster.ProcessGroupMember(addon, unitId, snapshot.sortIndexByGuid[playerGuid], snapshot.groupType)
    end

    addon.UI:UpdateUI()
end

function Roster.UpdateGroupMembers(addon)
    local snapshot = Roster.BuildSnapshot(addon)

    if not snapshot.groupType then
        addon:ClearAllTrackedPlayers()
        addon.wasGrouped = false
        if addon.RefreshCommsGroupState then
            addon:RefreshCommsGroupState()
        end
        return
    end

    if not addon.wasGrouped then
        addon:ClearTrackedPlayersForRosterTransition()
    end

    addon.wasGrouped = true
    Roster.Reconcile(addon, snapshot)
    if addon.RefreshCommsGroupState then
        addon:RefreshCommsGroupState()
    end
    addon:ProcessScanQueue()
end

local function ScheduleNameRetry(addon, playerGuid)
    addon.pendingRosterNameRetries = addon.pendingRosterNameRetries or {}
    if addon.pendingRosterNameRetries[playerGuid] then
        return false
    end

    local retryRecord = {}
    addon.pendingRosterNameRetries[playerGuid] = retryRecord

    retryRecord.timerHandle = addon:ScheduleManagedTimer(function()
        if addon.pendingRosterNameRetries[playerGuid] ~= retryRecord then
            return
        end

        addon.pendingRosterNameRetries[playerGuid] = nil

        local roster = addon.currentRoster
        local currentUnitId = roster and roster.unitIdByGuid
            and roster.unitIdByGuid[playerGuid]
        if not currentUnitId or UnitGUID(currentUnitId) ~= playerGuid then
            return
        end

        local processed = Roster.ProcessGroupMember(
            addon,
            currentUnitId,
            roster.sortIndexByGuid[playerGuid],
            roster.groupType
        )
        if processed then
            addon.UI:UpdateUI()
            addon:ProcessScanQueue()
        end
    end, Constants.PlayerNameRetryDelay, playerGuid)

    if not retryRecord.timerHandle
        and addon.pendingRosterNameRetries[playerGuid] == retryRecord then
        addon.pendingRosterNameRetries[playerGuid] = nil
        return false
    end

    return true
end

function Roster.ProcessGroupMember(addon, unitId, sortIndex, groupType)
    if not UnitExists(unitId) then return false end

    local playerGuid = UnitGUID(unitId)
    if not playerGuid then return false end

    local playerName, playerRealm = UnitName(unitId)
    local playerFullName = Players.GetUnitFullName(unitId)
        or Players.BuildFullName(playerName, playerRealm)
    local playerInfo = addon.PlayerStore:Get(playerGuid)

    if playerInfo then
        Roster.ApplyMetadata(playerInfo, playerGuid, unitId, sortIndex, groupType)
    end

    if not Players.IsKnownName(playerName) then
        ScheduleNameRetry(addon, playerGuid)
        return false
    end

    local isNewPlayer = false
    if not playerInfo then
        playerInfo = addon.PlayerStore:SetDefault(playerGuid)
        isNewPlayer = true
    end

    if not playerInfo then
        return false
    end

    playerInfo.PlayerName = playerName
    playerInfo.PlayerFullName = playerFullName or playerName
    Roster.ApplyMetadata(playerInfo, playerGuid, unitId, sortIndex, groupType)

    if isNewPlayer then
        addon:AddToScanQueue(playerGuid, true, ScanReason.Group)
    elseif playerInfo.CheckStatus == ScanStatus.TemporaryFailed then
        if not addon:HasScheduledPlayerWork(playerGuid) then
            playerInfo.CheckStatus = ScanStatus.InProgress
            playerInfo.retryAttempts = 0
            addon:AddToScanQueue(playerGuid, true, ScanReason.Group)
        end
    elseif playerInfo.CheckStatus == ScanStatus.Partial then
        if not addon:HasScheduledPlayerWork(playerGuid) then
            addon:AddToScanQueue(playerGuid, true, ScanReason.Group)
        end
    elseif not playerInfo.LastScanTime or playerInfo.LastScanTime <= 0 then
        addon:AddToScanQueue(playerGuid, true, ScanReason.Group)
    elseif (time() - playerInfo.LastScanTime) > Constants.StaleScanAgeSeconds then
        addon:AddToScanQueue(playerGuid, true, ScanReason.Group)
    end

    return true
end

function GearPolice:ResetRosterSnapshot()
    return Roster.ResetSnapshot(self)
end

function GearPolice:BuildGroupRosterSnapshot()
    return Roster.BuildSnapshot(self)
end

function GearPolice:RefreshCurrentRosterSnapshot()
    return Roster.RefreshSnapshot(self)
end

function GearPolice:ApplyCurrentRosterMetadata(playerGuid, playerInfo)
    return Roster.ApplyCurrentMetadata(self, playerGuid, playerInfo)
end

function GearPolice:RemoveGuidFromCurrentRoster(playerGuid)
    return Roster.RemoveGuidFromCurrent(self, playerGuid)
end

function GearPolice:UpdatePlayerGearInfoWithGroupMembers()
    return Roster.UpdateGroupMembers(self)
end
