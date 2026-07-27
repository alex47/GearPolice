local GearPolice = GearPolice

GearPolice.PlayerStore = GearPolice.PlayerStore or {}

local PlayerStore = GearPolice.PlayerStore
local Constants = GearPolice.Constants
local ScanStatus = GearPolice.Constants.ScanStatus

local function InitializeScanFields(playerInfo, scanGeneration)
    playerInfo.CheckRequested = true
    playerInfo.CheckStatus = ScanStatus.InProgress
    playerInfo.Problems = {}
    playerInfo.EquippedItems = {}
    playerInfo.PendingItemMetadata = {}
    playerInfo.LastScanTime = 0
    playerInfo.retryAttempts = 0
    playerInfo.pendingChecks = 0
    playerInfo.ForceScanRequested = true
    playerInfo.ScanGeneration = scanGeneration or 0
end

function PlayerStore:EnsureStorage()
    if not GearPolice.db or not GearPolice.db.global then
        return nil
    end

    if type(GearPolice.db.global.PlayerGearInfo) ~= "table" then
        GearPolice.db.global.PlayerGearInfo = {}
    end

    return GearPolice.db.global.PlayerGearInfo
end

function PlayerStore:GetAll()
    return self:EnsureStorage()
end

function PlayerStore:Get(playerGuid)
    if not playerGuid then
        return nil
    end

    local playerGearInfo = self:EnsureStorage()
    return playerGearInfo and playerGearInfo[playerGuid] or nil
end

function PlayerStore:SetDefault(playerGuid)
    if not playerGuid then
        return nil
    end

    local playerGearInfo = self:EnsureStorage()
    if not playerGearInfo then
        return nil
    end

    local _, _, _, _, _, playerName, playerRealm = GetPlayerInfoByGUID(playerGuid)
    local playerInfo = {
        PlayerName = GearPolice.Players.IsKnownName(playerName) and playerName or "Unknown",
        PlayerFullName = GearPolice.Players.BuildFullName(playerName, playerRealm) or "Unknown",
        PlayerGuid = playerGuid,
        IsRosterTracked = false,
    }
    InitializeScanFields(playerInfo, 0)
    playerGearInfo[playerGuid] = playerInfo

    return playerGearInfo[playerGuid]
end

function PlayerStore:Ensure(playerGuid)
    return self:Get(playerGuid) or self:SetDefault(playerGuid)
end

function PlayerStore:ResetForScan(playerGuid, playerName, playerFullName)
    local playerInfo = self:Ensure(playerGuid)
    if not playerInfo then
        return nil
    end

    playerInfo.PlayerName = GearPolice.Players.IsKnownName(playerName)
        and playerName or playerInfo.PlayerName or "Unknown"
    playerInfo.PlayerFullName = GearPolice.Players.IsKnownName(playerFullName)
        and playerFullName or playerInfo.PlayerFullName or playerInfo.PlayerName
    playerInfo.PlayerGuid = playerGuid
    InitializeScanFields(playerInfo, (playerInfo.ScanGeneration or 0) + 1)

    return playerInfo
end

function PlayerStore:Remove(playerGuid)
    local playerGearInfo = self:EnsureStorage()
    if playerGearInfo and playerGuid then
        playerGearInfo[playerGuid] = nil
    end
end

function PlayerStore:ClearAll()
    if GearPolice.db and GearPolice.db.global then
        GearPolice.db.global.PlayerGearInfo = {}
    end
end

function PlayerStore:MarkAllScansCancelled()
    local playerGearInfo = self:GetAll()
    if not playerGearInfo then
        return
    end

    for _, playerInfo in pairs(playerGearInfo) do
        playerInfo.CheckRequested = false
        playerInfo.CheckStatus = ScanStatus.Cancelled
        playerInfo.pendingChecks = 0
        playerInfo.ScanGeneration = (playerInfo.ScanGeneration or 0) + 1
    end
end

function PlayerStore:HasPendingEquippedItems(playerInfo)
    if not playerInfo or type(playerInfo.EquippedItems) ~= "table" then
        return true
    end

    for _, slotName in ipairs(GearPolice.Slots.GetInventorySlotNames()) do
        local slotValue = playerInfo.EquippedItems[slotName]
        if not slotValue or slotValue == Constants.InventorySlotPending then
            return true
        end
    end

    return false
end

function PlayerStore:HasPendingItemMetadata(playerInfo)
    if not playerInfo or type(playerInfo.PendingItemMetadata) ~= "table" then
        return false
    end

    return next(playerInfo.PendingItemMetadata) ~= nil
end

function PlayerStore:IsScanComplete(playerInfo)
    if not playerInfo then
        return false
    end

    if playerInfo.CheckStatus ~= ScanStatus.Successful then
        return false
    end

    return not self:HasPendingEquippedItems(playerInfo)
        and not self:HasPendingItemMetadata(playerInfo)
end

function GearPolice:SetPlayerGuidToDefaultInPlayerGearInfo(playerGuid)
    return PlayerStore:SetDefault(playerGuid)
end

function GearPolice:ResetPlayerGearInfo(playerGuid, playerName, playerFullName)
    local playerInfo = PlayerStore:ResetForScan(playerGuid, playerName, playerFullName)
    if not playerInfo then
        return
    end

    self:ApplyCurrentRosterMetadata(playerGuid, playerInfo)
    self:ClearScheduledWorkForPlayer(playerGuid)
end

function GearPolice:HasPendingEquippedItems(playerInfo)
    return PlayerStore:HasPendingEquippedItems(playerInfo)
end

function GearPolice:HasPendingItemMetadata(playerInfo)
    return PlayerStore:HasPendingItemMetadata(playerInfo)
end

function GearPolice:IsPlayerScanComplete(playerInfo)
    return PlayerStore:IsScanComplete(playerInfo)
end
