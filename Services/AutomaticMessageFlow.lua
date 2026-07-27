local GearPolice = GearPolice

GearPolice.AutomaticMessageFlow = GearPolice.AutomaticMessageFlow or {}

local AutomaticMessageFlow = GearPolice.AutomaticMessageFlow
local CooldownSeconds = GearPolice.Constants.AutomaticPlayerMessageCooldownSeconds
local CombatDelaySeconds = GearPolice.Constants.AutomaticMessageCombatDelaySeconds

local FlowMethods = {}

function AutomaticMessageFlow.Create(config)
    local flow = {
        config = config,
        pendingCoordination = {},
        pendingCombat = {},
    }

    for methodName, method in pairs(FlowMethods) do
        flow[methodName] = method
    end

    return flow
end

function FlowMethods:EnsureHistory()
    local db = GearPolice.db and GearPolice.db.global
    if not db then
        return {}
    end

    local historyKey = self.config.historyKey
    if type(db[historyKey]) ~= "table" then
        db[historyKey] = {}
    end

    return db[historyKey]
end

function FlowMethods:PruneExpiredHistory()
    local history = self:EnsureHistory()
    local timestampField = self.config.timestampField
    local currentTime = time()

    for playerGuid, historyEntry in pairs(history) do
        local timestamp = type(historyEntry) == "table" and historyEntry[timestampField] or nil
        if type(timestamp) ~= "number" or currentTime - timestamp >= CooldownSeconds then
            history[playerGuid] = nil
        end
    end
end

function FlowMethods:Record(playerGuid, scanGeneration)
    if not GearPolice.Players.IsPlayerGuid(playerGuid) then
        return false
    end

    self:EnsureHistory()[playerGuid] = {
        [self.config.timestampField] = time(),
        scanGeneration = scanGeneration,
    }
    return true
end

function FlowMethods:IsOnCooldown(playerGuid)
    local historyEntry = self:EnsureHistory()[playerGuid]
    local timestamp = type(historyEntry) == "table"
        and historyEntry[self.config.timestampField] or nil
    return type(timestamp) == "number" and time() - timestamp < CooldownSeconds
end

function FlowMethods:CanConsider(playerInfo, completedScan, status)
    return self.config.isEligible(playerInfo, completedScan, status) == true
end

function FlowMethods:CanSend(playerInfo, completedScan, status)
    if not self:CanConsider(playerInfo, completedScan, status) then
        return false
    end

    if self.config.isCoordinator and not self.config.isCoordinator() then
        return false
    end

    return not self:IsOnCooldown(playerInfo.PlayerGuid)
end

function FlowMethods:Queue(pendingQueue, playerInfo, completedScan)
    if type(playerInfo) ~= "table" or not playerInfo.PlayerGuid then
        return false
    end

    pendingQueue[playerInfo.PlayerGuid] = {
        scanGeneration = playerInfo.ScanGeneration,
        reason = completedScan and completedScan.reason,
    }
    return true
end

function FlowMethods:Send(playerInfo)
    if not self.config.send(playerInfo) then
        return false
    end

    self:Record(playerInfo.PlayerGuid, playerInfo.ScanGeneration)
    if self.config.afterSend then
        self.config.afterSend(playerInfo)
    end
    return true
end

function FlowMethods:MaybeSend(playerInfo, completedScan, status)
    if not self:CanConsider(playerInfo, completedScan, status) then
        return false
    end

    if GearPolice:IsCommsCoordinationWarmupActive() then
        return self:Queue(self.pendingCoordination, playerInfo, completedScan)
    end

    if not self:CanSend(playerInfo, completedScan, status) then
        return false
    end

    if InCombatLockdown() then
        return self:Queue(self.pendingCombat, playerInfo, completedScan)
    end

    return self:Send(playerInfo)
end

function FlowMethods:DeliverPending(pendingQueue, queueForCombat)
    local deliveredAny = false

    for playerGuid, pending in pairs(pendingQueue) do
        local playerInfo = GearPolice.PlayerStore:Get(playerGuid)
        local completedScan = {
            reason = pending.reason,
        }
        pendingQueue[playerGuid] = nil

        if playerInfo and playerInfo.ScanGeneration == pending.scanGeneration
            and self:CanSend(playerInfo, completedScan, playerInfo.CheckStatus) then
            if queueForCombat and InCombatLockdown() then
                deliveredAny = self:Queue(self.pendingCombat, playerInfo, completedScan)
                    or deliveredAny
            else
                deliveredAny = self:Send(playerInfo) or deliveredAny
            end
        end
    end

    return deliveredAny
end

function FlowMethods:SendPendingCoordination()
    return self:DeliverPending(self.pendingCoordination, true)
end

function FlowMethods:SendPendingCombat()
    if InCombatLockdown() then
        return false
    end

    return self:DeliverPending(self.pendingCombat, false)
end

function FlowMethods:SchedulePendingCombat()
    local timerField = self.config.timerField
    if GearPolice[timerField] or not next(self.pendingCombat) or InCombatLockdown() then
        return false
    end

    GearPolice[timerField] = GearPolice:ScheduleManagedTimer(function()
        GearPolice[timerField] = nil
        self:SendPendingCombat()
    end, CombatDelaySeconds)

    return GearPolice[timerField] ~= nil
end

function FlowMethods:CancelCombatTimerIfIdle()
    local timerField = self.config.timerField
    if next(self.pendingCombat) or not GearPolice[timerField] then
        return
    end

    GearPolice:CancelManagedTimer(GearPolice[timerField])
    GearPolice[timerField] = nil
end

function FlowMethods:ClearPending(playerGuid)
    if not playerGuid then
        return
    end

    self.pendingCoordination[playerGuid] = nil
    self.pendingCombat[playerGuid] = nil
    self:CancelCombatTimerIfIdle()
end

function FlowMethods:ClearAllPending()
    self.pendingCoordination = {}
    self.pendingCombat = {}

    local timerField = self.config.timerField
    if GearPolice[timerField] then
        GearPolice:CancelManagedTimer(GearPolice[timerField])
        GearPolice[timerField] = nil
    end
end

function FlowMethods:Initialize()
    self:EnsureHistory()
    self:PruneExpiredHistory()
end
