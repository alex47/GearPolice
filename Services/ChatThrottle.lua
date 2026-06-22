local GearPolice = GearPolice

GearPolice.ChatThrottle = GearPolice.ChatThrottle or {}

local ChatThrottle = GearPolice.ChatThrottle
local ChatPrefix = "GearPolice"
local DefaultPriority = "NORMAL"

local function IsValidPriority(priority)
    return priority == "BULK" or priority == "NORMAL"
end

local function BuildQueueName(chatType, destination, queueName)
    if type(queueName) == "string" and queueName ~= "" then
        return queueName
    end

    if type(destination) == "string" and destination ~= "" then
        return ChatPrefix .. ":" .. tostring(chatType or "SAY") .. ":" .. destination
    end

    return ChatPrefix .. ":" .. tostring(chatType or "SAY")
end

local function TryThrottledSend(message, chatType, destination, priority, queueName)
    if not ChatThrottleLib or type(ChatThrottleLib.SendChatMessage) ~= "function" or #message > 255 then
        return false
    end

    return pcall(
        ChatThrottleLib.SendChatMessage,
        ChatThrottleLib,
        priority,
        ChatPrefix,
        message,
        chatType,
        nil,
        destination,
        queueName
    )
end

function ChatThrottle:Send(message, chatType, destination, priority, queueName)
    if type(message) ~= "string" or message == "" then
        return false
    end

    chatType = chatType or "SAY"
    priority = IsValidPriority(priority) and priority or DefaultPriority

    local resolvedQueueName = BuildQueueName(chatType, destination, queueName)
    if TryThrottledSend(message, chatType, destination, priority, resolvedQueueName) then
        return true
    end

    SendChatMessage(message, chatType, nil, destination)
    return true
end
