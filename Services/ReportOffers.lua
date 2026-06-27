local GearPolice = GearPolice

GearPolice.ReportOffers = GearPolice.ReportOffers or {}

local ReportOffers = GearPolice.ReportOffers
local ReportOfferCooldownSeconds = 12 * 60 * 60
local ReportOfferCombatDelay = 5
local ChatFiltersRegistered = false
local SuppressedOutgoingMessages = {}
local PendingCombatOffers = {}
local PendingCoordinationOffers = {}

local ResponseMessages = {
    SuccessfulClean = "No issues were found in your equipped gear.",
    Partial = "Some item data is still pending. Try !gp again in a moment.",
    InProgress = "Your equipped gear is still being scanned. Try !gp again in a moment.",
    TemporaryFailed = "Your equipped gear could not be inspected yet. "
        .. "Move closer or wait a moment, then try !gp again.",
    Failed = "Your gear scan could not be completed.",
    Cancelled = "Your gear scan was cancelled. Ask for a rescan, then try !gp again.",
    NoScan = "No gear scan is available for you yet.",
}

local function IsKnownPlayerName(playerName)
    return type(playerName) == "string" and playerName ~= "" and playerName ~= "Unknown"
end

local function ShouldHideReportOfferWhispers()
    return GearPolice.db
        and GearPolice.db.global
        and GearPolice.db.global.HideReportOfferWhispers == true
end

local function NormalizeFullPlayerName(playerName)
    if not IsKnownPlayerName(playerName) then
        return nil
    end

    return string.lower(playerName)
end

local function NormalizeShortPlayerName(playerName)
    if not IsKnownPlayerName(playerName) then
        return nil
    end

    local normalizedName = playerName:match("^([^%-]+)") or playerName
    return string.lower(normalizedName)
end

local function IsPlayerGuid(value)
    return type(value) == "string" and string.find(value, "^Player%-") ~= nil
end

local function BuildOfferMessage(playerInfo)
    local issueCount = GearPolice.Reporting:GetReportableIssueCount(playerInfo)
    local issueWord = issueCount == 1 and "issue" or "issues"
    local verb = issueCount == 1 and "was" or "were"
    return tostring(issueCount) .. " " .. issueWord
        .. " " .. verb .. " found in your equipped gear. Whisper me \"!gp\" to get the full report."
end

local function GetWhisperRecipientForPlayer(playerInfo)
    if type(playerInfo) ~= "table" then
        return nil
    end

    local unitId = playerInfo.CurrentUnitId
    if type(unitId) == "string" and UnitGUID(unitId) == playerInfo.PlayerGuid then
        local unitName, unitRealm = UnitName(unitId)
        if IsKnownPlayerName(unitName) then
            if type(unitRealm) == "string" and unitRealm ~= "" then
                return unitName .. "-" .. unitRealm
            end

            return unitName
        end
    end

    if IsKnownPlayerName(playerInfo.PlayerFullName) then
        return playerInfo.PlayerFullName
    end

    if IsKnownPlayerName(playerInfo.PlayerName) then
        return playerInfo.PlayerName
    end

    return nil
end

local function GetStoredFullPlayerName(playerInfo)
    if type(playerInfo) ~= "table" then
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

local function ExtractWhisperSenderGuid(...)
    local expectedGuid = select(10, ...)
    if IsPlayerGuid(expectedGuid) then
        return expectedGuid
    end

    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if IsPlayerGuid(value) then
            return value
        end
    end

    return nil
end

local function AddMessageEventFilter(eventName, filterFunc)
    if ChatFrameUtil and type(ChatFrameUtil.AddMessageEventFilter) == "function" then
        ChatFrameUtil.AddMessageEventFilter(eventName, filterFunc)
        return true
    elseif type(ChatFrame_AddMessageEventFilter) == "function" then
        ChatFrame_AddMessageEventFilter(eventName, filterFunc)
        return true
    end

    return false
end

local function IncomingWhisperFilter(_frame, _eventName, message)
    if ShouldHideReportOfferWhispers() and ReportOffers:IsWhisperRequest(message) then
        return true
    end

    return false
end

local function OutgoingWhisperFilter(_frame, _eventName, message)
    if type(message) ~= "string" then
        return false
    end

    local suppressCount = SuppressedOutgoingMessages[message]
    if type(suppressCount) ~= "number" or suppressCount <= 0 then
        return false
    end

    if suppressCount == 1 then
        SuppressedOutgoingMessages[message] = nil
    else
        SuppressedOutgoingMessages[message] = suppressCount - 1
    end

    return ShouldHideReportOfferWhispers()
end

function ReportOffers:EnsureHistory()
    if type(GearPolice.db.global.ReportOfferHistory) ~= "table" then
        GearPolice.db.global.ReportOfferHistory = {}
    end

    return GearPolice.db.global.ReportOfferHistory
end

function ReportOffers:PruneExpiredHistory()
    local offerHistory = self:EnsureHistory()
    local currentTime = time()

    for playerGuid, historyEntry in pairs(offerHistory) do
        local lastOfferedAt = type(historyEntry) == "table" and historyEntry.lastOfferedAt or nil
        if type(lastOfferedAt) ~= "number" or currentTime - lastOfferedAt >= ReportOfferCooldownSeconds then
            offerHistory[playerGuid] = nil
        end
    end
end

function ReportOffers:HasPendingCombatOffers()
    return next(PendingCombatOffers) ~= nil
end

function ReportOffers:HasPendingCoordinationOffers()
    return next(PendingCoordinationOffers) ~= nil
end

function ReportOffers:CancelCombatOfferTimerIfIdle()
    if self:HasPendingCombatOffers() or not GearPolice.reportOfferCombatTimer then
        return
    end

    GearPolice:CancelTimer(GearPolice.reportOfferCombatTimer)
    if GearPolice.activeTimers then
        GearPolice.activeTimers[GearPolice.reportOfferCombatTimer] = nil
    end
    GearPolice.reportOfferCombatTimer = nil
end

function ReportOffers:ClearPendingCombatOffer(playerGuid)
    if not playerGuid then
        return
    end

    PendingCombatOffers[playerGuid] = nil
    PendingCoordinationOffers[playerGuid] = nil
    self:CancelCombatOfferTimerIfIdle()
end

function ReportOffers:ClearPendingCombatOffers()
    PendingCombatOffers = {}
    PendingCoordinationOffers = {}

    if GearPolice.reportOfferCombatTimer then
        GearPolice:CancelTimer(GearPolice.reportOfferCombatTimer)
        if GearPolice.activeTimers then
            GearPolice.activeTimers[GearPolice.reportOfferCombatTimer] = nil
        end
        GearPolice.reportOfferCombatTimer = nil
    end
end

function ReportOffers:QueueCombatOffer(playerInfo, completedScan, status)
    if type(playerInfo) ~= "table" or not playerInfo.PlayerGuid then
        return false
    end

    PendingCombatOffers[playerInfo.PlayerGuid] = {
        scanGeneration = playerInfo.ScanGeneration,
        status = status,
        reason = completedScan and completedScan.reason,
    }

    return true
end

function ReportOffers:QueueCoordinationOffer(playerInfo, completedScan, status)
    if type(playerInfo) ~= "table" or not playerInfo.PlayerGuid then
        return false
    end

    PendingCoordinationOffers[playerInfo.PlayerGuid] = {
        scanGeneration = playerInfo.ScanGeneration,
        status = status,
        reason = completedScan and completedScan.reason,
    }

    return true
end

function ReportOffers:SendOffer(playerInfo)
    local playerGuid = playerInfo.PlayerGuid
    local offerHistory = self:EnsureHistory()
    local recipientName = GetWhisperRecipientForPlayer(playerInfo)

    if not recipientName then
        return false
    end

    GearPolice.Reporting:SendStatusWhisper(
        recipientName,
        BuildOfferMessage(playerInfo),
        ShouldHideReportOfferWhispers(),
        "BULK"
    )
    offerHistory[playerGuid] = {
        lastOfferedAt = time(),
        scanGeneration = playerInfo.ScanGeneration,
    }

    return true
end

function ReportOffers:SendPendingCombatOffers()
    if InCombatLockdown() then
        return false
    end

    for playerGuid, pendingOffer in pairs(PendingCombatOffers) do
        local playerInfo = GearPolice.PlayerStore:Get(playerGuid)
        local completedScan = {
            reason = pendingOffer.reason,
        }

        PendingCombatOffers[playerGuid] = nil

        if playerInfo and playerInfo.ScanGeneration == pendingOffer.scanGeneration
            and self:CanSendOffer(playerInfo, completedScan, playerInfo.CheckStatus) then
            self:SendOffer(playerInfo)
        end
    end

    return true
end

function ReportOffers:SchedulePendingCombatOffers()
    if GearPolice.reportOfferCombatTimer or not self:HasPendingCombatOffers() or InCombatLockdown() then
        return false
    end

    GearPolice.reportOfferCombatTimer = GearPolice:ScheduleManagedTimer(function()
        GearPolice.reportOfferCombatTimer = nil
        ReportOffers:SendPendingCombatOffers()
    end, ReportOfferCombatDelay)

    return GearPolice.reportOfferCombatTimer ~= nil
end

function ReportOffers:RegisterChatFilters()
    if ChatFiltersRegistered then
        return
    end

    local incomingRegistered = AddMessageEventFilter("CHAT_MSG_WHISPER", IncomingWhisperFilter)
    local outgoingRegistered = AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", OutgoingWhisperFilter)

    ChatFiltersRegistered = incomingRegistered or outgoingRegistered
end

function ReportOffers:RegisterOutgoingSuppression(message)
    if not ShouldHideReportOfferWhispers() or type(message) ~= "string" or message == "" then
        return
    end

    SuppressedOutgoingMessages[message] = (SuppressedOutgoingMessages[message] or 0) + 1
end

function ReportOffers:IsWhisperRequest(message)
    if type(message) ~= "string" then
        return false
    end

    local normalizedMessage = string.lower(message)
    return string.find(normalizedMessage, "!gp", 1, true) ~= nil
        or string.find(normalizedMessage, "|gp", 1, true) ~= nil
end

function ReportOffers:FindPlayerInfo(senderGuid, senderName)
    if IsPlayerGuid(senderGuid) then
        local playerInfo = GearPolice.PlayerStore:Get(senderGuid)
        if playerInfo then
            return playerInfo
        end
    end

    local normalizedFullSenderName = NormalizeFullPlayerName(senderName)
    if not normalizedFullSenderName then
        return nil
    end

    local playerGearInfo = GearPolice.PlayerStore:GetAll()
    if not playerGearInfo then
        return nil
    end

    for _, playerInfo in pairs(playerGearInfo) do
        if NormalizeFullPlayerName(GetStoredFullPlayerName(playerInfo)) == normalizedFullSenderName then
            return playerInfo
        end
    end

    local normalizedShortSenderName = NormalizeShortPlayerName(senderName)
    local matchedPlayerInfo
    local matchCount = 0
    for _, playerInfo in pairs(playerGearInfo) do
        if NormalizeShortPlayerName(GetStoredFullPlayerName(playerInfo)) == normalizedShortSenderName then
            matchedPlayerInfo = playerInfo
            matchCount = matchCount + 1
        end
    end

    if matchCount == 1 then
        return matchedPlayerInfo
    end

    return nil
end

function ReportOffers:SendScanResponse(playerInfo, recipientName)
    local reporting = GearPolice.Reporting
    local suppressLocal = ShouldHideReportOfferWhispers()
    if type(recipientName) ~= "string" or recipientName == "" then
        return false
    end

    if type(playerInfo) ~= "table" then
        return reporting:SendStatusWhisper(recipientName, ResponseMessages.NoScan, suppressLocal)
    end

    local status = playerInfo.CheckStatus
    local reportableItems = reporting:GetReportableProblematicItems(playerInfo)

    if status == "Successful" then
        if #reportableItems > 0 then
            return reporting:SendProblematicItemsWhisper(playerInfo, recipientName, suppressLocal)
        end

        return reporting:SendStatusWhisper(recipientName, ResponseMessages.SuccessfulClean, suppressLocal)
    elseif status == "Partial" then
        return reporting:SendStatusWhisper(recipientName, ResponseMessages.Partial, suppressLocal)
    elseif status == "InProgress" then
        return reporting:SendStatusWhisper(recipientName, ResponseMessages.InProgress, suppressLocal)
    elseif status == "TemporaryFailed" then
        return reporting:SendStatusWhisper(recipientName, ResponseMessages.TemporaryFailed, suppressLocal)
    elseif status == "Failed" then
        return reporting:SendStatusWhisper(recipientName, ResponseMessages.Failed, suppressLocal)
    elseif status == "Cancelled" then
        return reporting:SendStatusWhisper(recipientName, ResponseMessages.Cancelled, suppressLocal)
    end

    return reporting:SendStatusWhisper(recipientName, ResponseMessages.NoScan, suppressLocal)
end

function ReportOffers:HandleWhisper(message, senderName, senderGuid)
    if not self:IsWhisperRequest(message) then
        return false
    end

    local playerInfo = self:FindPlayerInfo(senderGuid, senderName)
    return self:SendScanResponse(playerInfo, senderName)
end

function ReportOffers:CanConsiderOffer(playerInfo, completedScan, status)
    if GearPolice.db.global.ReportOfferEnabled ~= true then
        return false
    end

    if GearPolice.Settings:IsAutoWhisperInRaidOnly() and not IsInRaid() then
        return false
    end

    if status ~= "Successful" or not completedScan then
        return false
    end

    if type(playerInfo) ~= "table" or not GetWhisperRecipientForPlayer(playerInfo) then
        return false
    end

    local playerGuid = playerInfo.PlayerGuid
    if not playerGuid or GearPolice:IsLocalPlayerGuid(playerGuid) then
        return false
    end

    if not GearPolice.Helper:IsPlayerInGroup(playerGuid) then
        return false
    end

    if GearPolice.Reporting:GetReportableIssueCount(playerInfo) == 0 then
        return false
    end

    return true
end

function ReportOffers:CanSendOffer(playerInfo, completedScan, status)
    if not self:CanConsiderOffer(playerInfo, completedScan, status) then
        return false
    end

    if GearPolice.IsLocalReportOfferCoordinator and not GearPolice:IsLocalReportOfferCoordinator() then
        return false
    end

    local playerGuid = playerInfo.PlayerGuid
    local offerHistory = self:EnsureHistory()
    local lastOffer = offerHistory[playerGuid]
    local lastOfferedAt = type(lastOffer) == "table" and lastOffer.lastOfferedAt or 0
    if type(lastOfferedAt) ~= "number" then
        lastOfferedAt = 0
    end

    return time() - lastOfferedAt >= ReportOfferCooldownSeconds
end

function ReportOffers:MaybeSendOffer(playerInfo, completedScan, status)
    if not self:CanConsiderOffer(playerInfo, completedScan, status) then
        return false
    end

    if GearPolice.IsReportOfferCoordinationWarmupActive
        and GearPolice:IsReportOfferCoordinationWarmupActive() then
        return self:QueueCoordinationOffer(playerInfo, completedScan, status)
    end

    if not self:CanSendOffer(playerInfo, completedScan, status) then
        return false
    end

    if InCombatLockdown() then
        return self:QueueCombatOffer(playerInfo, completedScan, status)
    end

    return self:SendOffer(playerInfo)
end

function ReportOffers:SendPendingCoordinationOffers()
    if not self:HasPendingCoordinationOffers() then
        return false
    end

    for playerGuid, pendingOffer in pairs(PendingCoordinationOffers) do
        local playerInfo = GearPolice.PlayerStore:Get(playerGuid)
        local completedScan = {
            reason = pendingOffer.reason,
        }

        PendingCoordinationOffers[playerGuid] = nil

        if playerInfo and playerInfo.ScanGeneration == pendingOffer.scanGeneration
            and self:CanSendOffer(playerInfo, completedScan, playerInfo.CheckStatus) then
            if InCombatLockdown() then
                self:QueueCombatOffer(playerInfo, completedScan, playerInfo.CheckStatus)
            else
                self:SendOffer(playerInfo)
            end
        end
    end

    return true
end

function GearPolice:InitializeReportOffers()
    if type(self.db.global.ReportOfferEnabled) ~= "boolean" then
        self.db.global.ReportOfferEnabled = false
    end

    if type(self.db.global.ReportOfferHistory) ~= "table" then
        self.db.global.ReportOfferHistory = {}
    end

    ReportOffers:PruneExpiredHistory()

    if type(self.db.global.HideReportOfferWhispers) ~= "boolean" then
        self.db.global.HideReportOfferWhispers = false
    end

    ReportOffers:RegisterChatFilters()
end

function GearPolice:MaybeSendReportOffer(playerInfo, completedScan, status)
    return ReportOffers:MaybeSendOffer(playerInfo, completedScan, status)
end

function GearPolice:SchedulePendingReportOffersAfterCombat()
    return ReportOffers:SchedulePendingCombatOffers()
end

function GearPolice:SendPendingReportOffersAfterCoordination()
    return ReportOffers:SendPendingCoordinationOffers()
end

function GearPolice:ClearPendingReportOffer(playerGuid)
    return ReportOffers:ClearPendingCombatOffer(playerGuid)
end

function GearPolice:ClearPendingReportOffers()
    return ReportOffers:ClearPendingCombatOffers()
end

function GearPolice:RegisterReportOfferOutgoingWhisper(message)
    return ReportOffers:RegisterOutgoingSuppression(message)
end

function GearPolice:OnReportOfferWhisperReceived(_eventName, message, senderName, ...)
    local senderGuid = ExtractWhisperSenderGuid(...)
    return ReportOffers:HandleWhisper(message, senderName, senderGuid)
end
