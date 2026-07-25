local GearPolice = GearPolice

GearPolice.PublicAnnouncements = GearPolice.PublicAnnouncements or {}

local PublicAnnouncements = GearPolice.PublicAnnouncements
local CooldownSeconds = GearPolice.Constants.AutomaticPlayerMessageCooldownSeconds
local CombatDelaySeconds = 5
local PendingCoordinationAnnouncements = {}
local PendingCombatAnnouncements = {}

local function IsGrouped()
    return IsInRaid() or IsInGroup()
end

function PublicAnnouncements:EnsureHistory()
    if type(GearPolice.db.global.PublicScanAnnouncementHistory) ~= "table" then
        GearPolice.db.global.PublicScanAnnouncementHistory = {}
    end

    return GearPolice.db.global.PublicScanAnnouncementHistory
end

function PublicAnnouncements:PruneExpiredHistory()
    local history = self:EnsureHistory()
    local currentTime = time()

    for playerGuid, historyEntry in pairs(history) do
        local lastAnnouncedAt = type(historyEntry) == "table" and historyEntry.lastAnnouncedAt or nil
        if type(lastAnnouncedAt) ~= "number"
            or currentTime - lastAnnouncedAt >= CooldownSeconds then
            history[playerGuid] = nil
        end
    end
end

function PublicAnnouncements:RecordAnnouncement(playerGuid, scanGeneration)
    if type(playerGuid) ~= "string" or playerGuid == "" then
        return false
    end

    self:EnsureHistory()[playerGuid] = {
        lastAnnouncedAt = time(),
        scanGeneration = scanGeneration,
    }
    return true
end

function PublicAnnouncements:IsOnCooldown(playerGuid)
    local historyEntry = self:EnsureHistory()[playerGuid]
    local lastAnnouncedAt = type(historyEntry) == "table" and historyEntry.lastAnnouncedAt or nil
    return type(lastAnnouncedAt) == "number"
        and time() - lastAnnouncedAt < CooldownSeconds
end

function PublicAnnouncements:CanConsider(playerInfo, completedScan, status)
    if not GearPolice.Settings:IsPublicScanAnnouncementEnabledForCurrentGroup()
        or not IsGrouped()
        or status ~= "Successful"
        or type(completedScan) ~= "table"
        or type(playerInfo) ~= "table" then
        return false
    end

    local playerGuid = playerInfo.PlayerGuid
    if type(playerGuid) ~= "string"
        or not GearPolice.Helper:IsPlayerInGroup(playerGuid)
        or GearPolice.Reporting:GetReportableIssueCount(playerInfo) <= 0 then
        return false
    end

    return GearPolice.Reporting:BuildPublicScanSummaryMessage(playerInfo) ~= nil
end

function PublicAnnouncements:CanSend(playerInfo, completedScan, status)
    if not self:CanConsider(playerInfo, completedScan, status) then
        return false
    end

    if GearPolice.IsLocalPublicAnnouncementCoordinator
        and not GearPolice:IsLocalPublicAnnouncementCoordinator() then
        return false
    end

    return not self:IsOnCooldown(playerInfo.PlayerGuid)
end

function PublicAnnouncements:QueueCoordination(playerInfo, completedScan)
    PendingCoordinationAnnouncements[playerInfo.PlayerGuid] = {
        scanGeneration = playerInfo.ScanGeneration,
        reason = completedScan.reason,
    }
    return true
end

function PublicAnnouncements:QueueCombat(playerInfo, completedScan)
    PendingCombatAnnouncements[playerInfo.PlayerGuid] = {
        scanGeneration = playerInfo.ScanGeneration,
        reason = completedScan.reason,
    }
    return true
end

function PublicAnnouncements:Send(playerInfo)
    local message = GearPolice.Reporting:BuildPublicScanSummaryMessage(playerInfo)
    if not message then
        return false
    end

    local sent = GearPolice.ChatThrottle:Send(
        message,
        IsInRaid() and "RAID" or "PARTY",
        nil,
        "NORMAL"
    )
    if not sent then
        return false
    end

    self:RecordAnnouncement(playerInfo.PlayerGuid, playerInfo.ScanGeneration)
    if GearPolice.AnnouncePublicScanSummarySent then
        GearPolice:AnnouncePublicScanSummarySent(playerInfo.PlayerGuid)
    end

    return true
end

function PublicAnnouncements:MaybeSend(playerInfo, completedScan, status)
    if not self:CanConsider(playerInfo, completedScan, status) then
        return false
    end

    if GearPolice.IsCommsCoordinationWarmupActive
        and GearPolice:IsCommsCoordinationWarmupActive() then
        return self:QueueCoordination(playerInfo, completedScan)
    end

    if not self:CanSend(playerInfo, completedScan, status) then
        return false
    end

    if InCombatLockdown() then
        return self:QueueCombat(playerInfo, completedScan)
    end

    return self:Send(playerInfo)
end

function PublicAnnouncements:SendPendingCoordination()
    for playerGuid, pending in pairs(PendingCoordinationAnnouncements) do
        local playerInfo = GearPolice.PlayerStore:Get(playerGuid)
        local completedScan = {
            reason = pending.reason,
        }

        PendingCoordinationAnnouncements[playerGuid] = nil

        if playerInfo and playerInfo.ScanGeneration == pending.scanGeneration
            and self:CanSend(playerInfo, completedScan, playerInfo.CheckStatus) then
            if InCombatLockdown() then
                self:QueueCombat(playerInfo, completedScan)
            else
                self:Send(playerInfo)
            end
        end
    end
end

function PublicAnnouncements:SendPendingCombat()
    if InCombatLockdown() then
        return false
    end

    for playerGuid, pending in pairs(PendingCombatAnnouncements) do
        local playerInfo = GearPolice.PlayerStore:Get(playerGuid)
        local completedScan = {
            reason = pending.reason,
        }

        PendingCombatAnnouncements[playerGuid] = nil

        if playerInfo and playerInfo.ScanGeneration == pending.scanGeneration
            and self:CanSend(playerInfo, completedScan, playerInfo.CheckStatus) then
            self:Send(playerInfo)
        end
    end

    return true
end

function PublicAnnouncements:SchedulePendingCombat()
    if GearPolice.publicAnnouncementCombatTimer
        or not next(PendingCombatAnnouncements)
        or InCombatLockdown() then
        return false
    end

    GearPolice.publicAnnouncementCombatTimer = GearPolice:ScheduleManagedTimer(function()
        GearPolice.publicAnnouncementCombatTimer = nil
        PublicAnnouncements:SendPendingCombat()
    end, CombatDelaySeconds)

    return GearPolice.publicAnnouncementCombatTimer ~= nil
end

function PublicAnnouncements:ClearPending(playerGuid)
    if not playerGuid then
        return
    end

    PendingCoordinationAnnouncements[playerGuid] = nil
    PendingCombatAnnouncements[playerGuid] = nil

    if not next(PendingCombatAnnouncements) and GearPolice.publicAnnouncementCombatTimer then
        GearPolice:CancelTimer(GearPolice.publicAnnouncementCombatTimer)
        if GearPolice.activeTimers then
            GearPolice.activeTimers[GearPolice.publicAnnouncementCombatTimer] = nil
        end
        GearPolice.publicAnnouncementCombatTimer = nil
    end
end

function PublicAnnouncements:ClearAllPending()
    PendingCoordinationAnnouncements = {}
    PendingCombatAnnouncements = {}

    if GearPolice.publicAnnouncementCombatTimer then
        GearPolice:CancelTimer(GearPolice.publicAnnouncementCombatTimer)
        if GearPolice.activeTimers then
            GearPolice.activeTimers[GearPolice.publicAnnouncementCombatTimer] = nil
        end
        GearPolice.publicAnnouncementCombatTimer = nil
    end
end

function GearPolice:InitializePublicScanAnnouncements()
    PublicAnnouncements:EnsureHistory()
    PublicAnnouncements:PruneExpiredHistory()
end

function GearPolice:MaybeAnnouncePublicScanSummary(playerInfo, completedScan, status)
    return PublicAnnouncements:MaybeSend(playerInfo, completedScan, status)
end

function GearPolice:SendPendingPublicScanAnnouncementsAfterCoordination()
    return PublicAnnouncements:SendPendingCoordination()
end

function GearPolice:SchedulePendingPublicScanAnnouncementsAfterCombat()
    return PublicAnnouncements:SchedulePendingCombat()
end

function GearPolice:ClearPendingPublicScanAnnouncement(playerGuid)
    return PublicAnnouncements:ClearPending(playerGuid)
end

function GearPolice:ClearPendingPublicScanAnnouncements()
    return PublicAnnouncements:ClearAllPending()
end

function GearPolice:RecordPublicScanAnnouncement(playerGuid)
    return PublicAnnouncements:RecordAnnouncement(playerGuid)
end
