local GearPolice = GearPolice

GearPolice.Timers = GearPolice.Timers or {}

local Timers = GearPolice.Timers

function Timers.ScheduleManagedTimer(addon, callback, delay, playerGuid)
    if type(callback) ~= "function" or not delay then
        return nil
    end

    addon.activeTimers = addon.activeTimers or {}
    addon.activePlayerTimers = addon.activePlayerTimers or {}

    local handle
    handle = addon:ScheduleTimer(function()
        if addon.activeTimers then
            addon.activeTimers[handle] = nil
        end
        if playerGuid and addon.activePlayerTimers and addon.activePlayerTimers[playerGuid] then
            addon.activePlayerTimers[playerGuid][handle] = nil
            if not next(addon.activePlayerTimers[playerGuid]) then
                addon.activePlayerTimers[playerGuid] = nil
            end
        end
        callback()
    end, delay)

    if handle then
        addon.activeTimers[handle] = playerGuid or true
        if playerGuid then
            addon.activePlayerTimers[playerGuid] = addon.activePlayerTimers[playerGuid] or {}
            addon.activePlayerTimers[playerGuid][handle] = true
        end
    end

    return handle
end

function Timers.CancelManagedTimersForPlayer(addon, playerGuid)
    if not playerGuid or not addon.activePlayerTimers then
        return
    end

    local timers = addon.activePlayerTimers[playerGuid]
    if not timers then
        return
    end

    for handle in pairs(timers) do
        addon:CancelTimer(handle)
        if addon.activeTimers then
            addon.activeTimers[handle] = nil
        end
    end

    addon.activePlayerTimers[playerGuid] = nil
end

function Timers.CancelAllManagedTimers(addon)
    if not addon.activeTimers then
        return
    end

    for handle in pairs(addon.activeTimers) do
        addon:CancelTimer(handle)
    end

    addon.activeTimers = {}
    addon.activePlayerTimers = {}
    addon.scanQueueTimer = nil
    addon.reportOfferCombatTimer = nil
end

function GearPolice:ScheduleManagedTimer(callback, delay, playerGuid)
    return Timers.ScheduleManagedTimer(self, callback, delay, playerGuid)
end

function GearPolice:CancelManagedTimersForPlayer(playerGuid)
    return Timers.CancelManagedTimersForPlayer(self, playerGuid)
end

function GearPolice:CancelAllManagedTimers()
    return Timers.CancelAllManagedTimers(self)
end
