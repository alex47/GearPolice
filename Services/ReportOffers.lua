local GearPolice = GearPolice

GearPolice.ReportOffers = GearPolice.ReportOffers or {}

local ReportOffers = GearPolice.ReportOffers
local ScanStatus = GearPolice.Constants.ScanStatus
local ChatFiltersRegistered = false
local SuppressedOutgoingMessages = {}

local ResponseMessages = {
    SuccessfulClean = "No issues were found in your equipped gear.",
    [ScanStatus.Partial] = "Some item data is still pending. Try !gp again in a moment.",
    [ScanStatus.InProgress] = "Your equipped gear is still being scanned. Try !gp again in a moment.",
    [ScanStatus.TemporaryFailed] = "Your equipped gear could not be inspected yet. "
        .. "Move closer or wait a moment, then try !gp again.",
    [ScanStatus.Failed] = "Your gear scan could not be completed.",
    [ScanStatus.Cancelled] = "Your gear scan was cancelled. Ask for a rescan, then try !gp again.",
    NoScan = "No gear scan is available for you yet.",
}

local function ShouldHideReportOfferWhispers()
    return not GearPolice.Settings:IsAutoWhispersShown()
end

local function ExtractWhisperSenderGuid(...)
    local expectedGuid = select(10, ...)
    if GearPolice.Players.IsPlayerGuid(expectedGuid) then
        return expectedGuid
    end

    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if GearPolice.Players.IsPlayerGuid(value) then
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
    return ShouldHideReportOfferWhispers() and ReportOffers:IsWhisperRequest(message)
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
    if GearPolice.Players.IsPlayerGuid(senderGuid) then
        local playerInfo = GearPolice.PlayerStore:Get(senderGuid)
        if playerInfo then
            return playerInfo
        end
    end

    local normalizedFullSenderName = GearPolice.Players.NormalizeFullName(senderName)
    if not normalizedFullSenderName then
        return nil
    end

    local playerGearInfo = GearPolice.PlayerStore:GetAll()
    for _, playerInfo in pairs(playerGearInfo or {}) do
        local storedName = GearPolice.Players.GetStoredFullName(playerInfo)
        if GearPolice.Players.NormalizeFullName(storedName) == normalizedFullSenderName then
            return playerInfo
        end
    end

    local normalizedShortSenderName = GearPolice.Players.NormalizeShortName(senderName)
    local matchedPlayerInfo
    local matchCount = 0
    for _, playerInfo in pairs(playerGearInfo or {}) do
        local storedName = GearPolice.Players.GetStoredFullName(playerInfo)
        if GearPolice.Players.NormalizeShortName(storedName) == normalizedShortSenderName then
            matchedPlayerInfo = playerInfo
            matchCount = matchCount + 1
        end
    end

    return matchCount == 1 and matchedPlayerInfo or nil
end

function ReportOffers:SendScanResponse(playerInfo, recipientName)
    local reporting = GearPolice.Reporting
    local suppressLocal = ShouldHideReportOfferWhispers()
    if not GearPolice.Players.IsKnownName(recipientName) then
        return false
    end

    if type(playerInfo) ~= "table" then
        return reporting:SendStatusWhisper(recipientName, ResponseMessages.NoScan, suppressLocal)
    end

    local status = playerInfo.CheckStatus
    if status == ScanStatus.Successful then
        if reporting:GetReportableIssueCount(playerInfo) > 0 then
            return reporting:SendProblematicItemsWhisper(playerInfo, recipientName, suppressLocal)
        end

        return reporting:SendStatusWhisper(
            recipientName,
            ResponseMessages.SuccessfulClean,
            suppressLocal
        )
    end

    return reporting:SendStatusWhisper(
        recipientName,
        ResponseMessages[status] or ResponseMessages.NoScan,
        suppressLocal
    )
end

function ReportOffers:HandleWhisper(message, senderName, senderGuid)
    if not self:IsWhisperRequest(message) then
        return false
    end

    return self:SendScanResponse(self:FindPlayerInfo(senderGuid, senderName), senderName)
end

local function IsEligible(playerInfo, completedScan, status)
    if not GearPolice.Settings:IsReportOfferEnabled()
        or not GearPolice.Settings:IsAutoWhisperEnabledForCurrentGroup()
        or status ~= ScanStatus.Successful
        or type(completedScan) ~= "table"
        or type(playerInfo) ~= "table"
        or not GearPolice.Players.GetWhisperRecipient(playerInfo) then
        return false
    end

    local playerGuid = playerInfo.PlayerGuid
    return GearPolice.Players.IsPlayerGuid(playerGuid)
        and not GearPolice:IsLocalPlayerGuid(playerGuid)
        and GearPolice.Units.IsPlayerInGroup(playerGuid)
        and GearPolice.Reporting:GetReportableIssueCount(playerInfo) > 0
end

local function SendOffer(playerInfo)
    local recipientName = GearPolice.Players.GetWhisperRecipient(playerInfo)
    local messages = GearPolice.Reporting:BuildReportOfferMessages(playerInfo)
    if not recipientName or #messages == 0 then
        return false
    end

    local suppressLocal = ShouldHideReportOfferWhispers()
    for _, message in ipairs(messages) do
        if not GearPolice.Reporting:SendWhisper(recipientName, message, suppressLocal, "BULK") then
            return false
        end
    end

    return true
end

ReportOffers.Flow = GearPolice.AutomaticMessageFlow.Create({
    historyKey = "ReportOfferHistory",
    timestampField = "lastOfferedAt",
    timerField = "reportOfferCombatTimer",
    isEligible = IsEligible,
    isCoordinator = function()
        return GearPolice:IsLocalReportOfferCoordinator()
    end,
    send = SendOffer,
})

function GearPolice:InitializeReportOffers()
    ReportOffers.Flow:Initialize()
    ReportOffers:RegisterChatFilters()
end

function GearPolice:MaybeSendReportOffer(playerInfo, completedScan, status)
    return ReportOffers.Flow:MaybeSend(playerInfo, completedScan, status)
end

function GearPolice:SchedulePendingReportOffersAfterCombat()
    return ReportOffers.Flow:SchedulePendingCombat()
end

function GearPolice:SendPendingReportOffersAfterCoordination()
    return ReportOffers.Flow:SendPendingCoordination()
end

function GearPolice:ClearPendingReportOffer(playerGuid)
    return ReportOffers.Flow:ClearPending(playerGuid)
end

function GearPolice:ClearPendingReportOffers()
    return ReportOffers.Flow:ClearAllPending()
end

function GearPolice:RegisterReportOfferOutgoingWhisper(message)
    return ReportOffers:RegisterOutgoingSuppression(message)
end

function GearPolice:OnReportOfferWhisperReceived(_eventName, message, senderName, ...)
    local senderGuid = ExtractWhisperSenderGuid(...)
    return ReportOffers:HandleWhisper(message, senderName, senderGuid)
end
