local GearPolice = GearPolice

GearPolice.ReportOffers = GearPolice.ReportOffers or {}

local ReportOffers = GearPolice.ReportOffers
local ReportOfferCooldownSeconds = 12 * 60 * 60
local ReportOfferCombatDelay = 5
local ChatFiltersRegistered = false
local SuppressedOutgoingMessages = {}
local PendingCombatOffers = {}

local ResponseMessages = {
    SuccessfulClean = "No issues found in your equipped gear.",
    Partial = "Your gear scan is waiting on item data. Try !gp again in a moment.",
    InProgress = "Your gear scan is still running. Try !gp again in a moment.",
    TemporaryFailed = "I could not inspect you yet. Move closer or wait a moment, then try !gp again.",
    Failed = "I could not complete your gear scan. Ask for a rescan if needed.",
    Cancelled = "Your gear scan was cancelled. Ask for a rescan, then try !gp again.",
    NoScan = "I do not have a gear scan for you yet.",
    Offer = "I found issues with your equipped gear. Reply !gp for details.",
}

local function IsKnownPlayerName(playerName)
    return type(playerName) == "string" and playerName ~= "" and playerName ~= "Unknown"
end

local function ShouldHideReportOfferWhispers()
    return GearPolice.db
        and GearPolice.db.global
        and GearPolice.db.global.HideReportOfferWhispers == true
end

local function NormalizePlayerName(playerName)
    if not IsKnownPlayerName(playerName) then
        return nil
    end

    local normalizedName = playerName:match("^([^%-]+)") or playerName
    return string.lower(normalizedName)
end

local function IsPlayerGuid(value)
    return type(value) == "string" and string.find(value, "^Player%-") ~= nil
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

function ReportOffers:HasPendingCombatOffers()
    return next(PendingCombatOffers) ~= nil
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

function ReportOffers:SendOffer(playerInfo)
    local playerGuid = playerInfo.PlayerGuid
    local offerHistory = self:EnsureHistory()
    local recipientName = GetWhisperRecipientForPlayer(playerInfo)

    if not recipientName then
        return false
    end

    GearPolice.Reporting:SendStatusWhisper(recipientName, ResponseMessages.Offer, ShouldHideReportOfferWhispers())
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

    return string.find(string.lower(message), "!gp", 1, true) ~= nil
end

function ReportOffers:FindPlayerInfo(senderGuid, senderName)
    if IsPlayerGuid(senderGuid) then
        local playerInfo = GearPolice.PlayerStore:Get(senderGuid)
        if playerInfo then
            return playerInfo
        end
    end

    local normalizedSenderName = NormalizePlayerName(senderName)
    if not normalizedSenderName then
        return nil
    end

    local playerGearInfo = GearPolice.PlayerStore:GetAll()
    if not playerGearInfo then
        return nil
    end

    for _, playerInfo in pairs(playerGearInfo) do
        if NormalizePlayerName(playerInfo.PlayerName) == normalizedSenderName then
            return playerInfo
        end
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

function ReportOffers:CanSendOffer(playerInfo, completedScan, status)
    if GearPolice.db.global.ReportOfferEnabled ~= true then
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

    if #GearPolice.Reporting:GetReportableProblematicItems(playerInfo) == 0 then
        return false
    end

    local offerHistory = self:EnsureHistory()
    local lastOffer = offerHistory[playerGuid]
    local lastOfferedAt = type(lastOffer) == "table" and lastOffer.lastOfferedAt or 0
    if type(lastOfferedAt) ~= "number" then
        lastOfferedAt = 0
    end

    return time() - lastOfferedAt >= ReportOfferCooldownSeconds
end

function ReportOffers:MaybeSendOffer(playerInfo, completedScan, status)
    if not self:CanSendOffer(playerInfo, completedScan, status) then
        return false
    end

    if InCombatLockdown() then
        return self:QueueCombatOffer(playerInfo, completedScan, status)
    end

    return self:SendOffer(playerInfo)
end

function GearPolice:InitializeReportOffers()
    if type(self.db.global.ReportOfferEnabled) ~= "boolean" then
        self.db.global.ReportOfferEnabled = false
    end

    if type(self.db.global.ReportOfferHistory) ~= "table" then
        self.db.global.ReportOfferHistory = {}
    end

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

function GearPolice:RegisterReportOfferOutgoingWhisper(message)
    return ReportOffers:RegisterOutgoingSuppression(message)
end

function GearPolice:OnReportOfferWhisperReceived(_eventName, message, senderName, ...)
    local senderGuid = ExtractWhisperSenderGuid(...)
    return ReportOffers:HandleWhisper(message, senderName, senderGuid)
end
