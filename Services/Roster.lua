local GearPolice = GearPolice

GearPolice.Roster = GearPolice.Roster or {}

local Roster = GearPolice.Roster

local function BuildFullPlayerName(playerName, playerRealm)
    if type(playerName) ~= "string" or playerName == "" or playerName == "Unknown" then
        return nil
    end

    if type(playerRealm) == "string" and playerRealm ~= "" then
        return playerName .. "-" .. playerRealm
    end

    return playerName
end

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

function Roster.GetOrderedPlayerGuids(addon)
    local orderedGuids = {}
    local includedGuids = {}
    local playerGearInfo = addon.PlayerStore:GetAll()

    if not playerGearInfo then
        return orderedGuids
    end

    local roster = addon.currentRoster

    if roster and roster.orderedGuids then
        for _, playerGuid in ipairs(roster.orderedGuids) do
            if playerGearInfo[playerGuid] then
                table.insert(orderedGuids, playerGuid)
                includedGuids[playerGuid] = true
            end
        end
    end

    local nonRosterPlayers = {}
    for playerGuid, playerInfo in pairs(playerGearInfo) do
        if not includedGuids[playerGuid] then
            table.insert(nonRosterPlayers, {
                playerGuid = playerGuid,
                playerName = playerInfo.PlayerName or "Unknown",
            })
        end
    end

    table.sort(nonRosterPlayers, function(a, b)
        local nameA = string.lower(a.playerName or "")
        local nameB = string.lower(b.playerName or "")

        if nameA == nameB then
            return (a.playerGuid or "") < (b.playerGuid or "")
        end

        return nameA < nameB
    end)

    for _, player in ipairs(nonRosterPlayers) do
        table.insert(orderedGuids, player.playerGuid)
    end

    return orderedGuids
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

function Roster.ProcessGroupMember(addon, unitId, sortIndex, groupType)
    if not UnitExists(unitId) then return end

    local playerGuid = UnitGUID(unitId)
    if not playerGuid then return end

    local playerName, playerRealm = UnitName(unitId)
    local playerFullName = BuildFullPlayerName(playerName, playerRealm)
    local playerInfo = addon.PlayerStore:Get(playerGuid)

    if playerInfo then
        Roster.ApplyMetadata(playerInfo, playerGuid, unitId, sortIndex, groupType)
    end

    if not playerName or playerName == "Unknown" then
        addon:ScheduleManagedTimer(function()
            local roster = addon.currentRoster
            local currentUnitId = roster and roster.unitIdByGuid and roster.unitIdByGuid[playerGuid]
            if currentUnitId and UnitGUID(currentUnitId) == playerGuid then
                Roster.ProcessGroupMember(
                    addon,
                    currentUnitId,
                    roster.sortIndexByGuid[playerGuid],
                    roster.groupType
                )
            end
        end, 1, playerGuid)
        return
    end

    local isNewPlayer = false
    if not playerInfo then
        playerInfo = addon.PlayerStore:SetDefault(playerGuid)
        isNewPlayer = true
    end

    if not playerInfo then
        return
    end

    playerInfo.PlayerName = playerName
    playerInfo.PlayerFullName = playerFullName or playerName
    Roster.ApplyMetadata(playerInfo, playerGuid, unitId, sortIndex, groupType)

    if isNewPlayer then
        addon:AddToScanQueue(playerGuid, true, "group")
    elseif playerInfo.CheckStatus == "TemporaryFailed" then
        if not addon:HasScheduledPlayerWork(playerGuid) then
            playerInfo.CheckStatus = "InProgress"
            playerInfo.retryAttempts = 0
            addon:AddToScanQueue(playerGuid, true, "group")
        end
    elseif playerInfo.CheckStatus == "Partial" then
        if not addon:HasScheduledPlayerWork(playerGuid) then
            addon:AddToScanQueue(playerGuid, true, "group")
        end
    elseif not playerInfo.LastScanTime or playerInfo.LastScanTime <= 0 then
        addon:AddToScanQueue(playerGuid, true, "group")
    elseif (time() - playerInfo.LastScanTime) > 86400 then
        addon:AddToScanQueue(playerGuid, true, "group")
    end
end

function GearPolice:CreateEmptyRosterSnapshot(groupType)
    return Roster.CreateEmptySnapshot(groupType)
end

function GearPolice:ResetRosterSnapshot()
    return Roster.ResetSnapshot(self)
end

function GearPolice:BuildGroupRosterSnapshot()
    return Roster.BuildSnapshot(self)
end

function GearPolice:ApplyRosterMetadata(playerInfo, playerGuid, unitId, sortIndex, groupType)
    return Roster.ApplyMetadata(playerInfo, playerGuid, unitId, sortIndex, groupType)
end

function GearPolice:ClearRosterMetadata(playerInfo)
    return Roster.ClearMetadata(playerInfo)
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

function GearPolice:GetOrderedPlayerGuids()
    return Roster.GetOrderedPlayerGuids(self)
end

function GearPolice:ReconcileGroupRoster(snapshot)
    Roster.Reconcile(self, snapshot)
    if self.RefreshCommsGroupState then
        self:RefreshCommsGroupState()
    end
    return self:ProcessScanQueue()
end

function GearPolice:UpdatePlayerGearInfoWithGroupMembers()
    return Roster.UpdateGroupMembers(self)
end

function GearPolice:ProcessGroupMember(unitId, sortIndex, groupType)
    return Roster.ProcessGroupMember(self, unitId, sortIndex, groupType)
end
