local GearPolice = GearPolice

GearPolice.PublicAnnouncements = GearPolice.PublicAnnouncements or {}

local PublicAnnouncements = GearPolice.PublicAnnouncements
local ScanStatus = GearPolice.Constants.ScanStatus

local function IsEligible(playerInfo, completedScan, status)
    if not GearPolice.Settings:IsPublicScanAnnouncementEnabledForCurrentGroup()
        or status ~= ScanStatus.Successful
        or type(completedScan) ~= "table"
        or type(playerInfo) ~= "table" then
        return false
    end

    local playerGuid = playerInfo.PlayerGuid
    if not GearPolice.Players.IsPlayerGuid(playerGuid)
        or not GearPolice.Units.IsPlayerInGroup(playerGuid)
        or GearPolice.Reporting:GetReportableIssueCount(playerInfo) <= 0 then
        return false
    end

    return #GearPolice.Reporting:BuildPublicScanSummaryMessages(playerInfo) > 0
end

local function SendMessages(playerInfo)
    local chatType = GearPolice.Units.GetGroupChatType()
    local messages = GearPolice.Reporting:BuildPublicScanSummaryMessages(playerInfo)
    if not chatType or #messages == 0 then
        return false
    end

    for _, message in ipairs(messages) do
        if not GearPolice.ChatThrottle:Send(message, chatType, nil, "NORMAL") then
            return false
        end
    end

    return true
end

local function AfterSend(playerInfo)
    if GearPolice.AnnouncePublicScanSummarySent then
        GearPolice:AnnouncePublicScanSummarySent(playerInfo.PlayerGuid)
    end
end

PublicAnnouncements.Flow = GearPolice.AutomaticMessageFlow.Create({
    historyKey = "PublicScanAnnouncementHistory",
    timestampField = "lastAnnouncedAt",
    timerField = "publicAnnouncementCombatTimer",
    isEligible = IsEligible,
    isCoordinator = function()
        return GearPolice:IsLocalPublicAnnouncementCoordinator()
    end,
    send = SendMessages,
    afterSend = AfterSend,
})

function GearPolice:InitializePublicScanAnnouncements()
    return PublicAnnouncements.Flow:Initialize()
end

function GearPolice:MaybeAnnouncePublicScanSummary(playerInfo, completedScan, status)
    return PublicAnnouncements.Flow:MaybeSend(playerInfo, completedScan, status)
end

function GearPolice:SendPendingPublicScanAnnouncementsAfterCoordination()
    return PublicAnnouncements.Flow:SendPendingCoordination()
end

function GearPolice:SchedulePendingPublicScanAnnouncementsAfterCombat()
    return PublicAnnouncements.Flow:SchedulePendingCombat()
end

function GearPolice:ClearPendingPublicScanAnnouncement(playerGuid)
    return PublicAnnouncements.Flow:ClearPending(playerGuid)
end

function GearPolice:ClearPendingPublicScanAnnouncements()
    return PublicAnnouncements.Flow:ClearAllPending()
end

function GearPolice:RecordPublicScanAnnouncement(playerGuid)
    return PublicAnnouncements.Flow:Record(playerGuid)
end
