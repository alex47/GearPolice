local GearPolice = GearPolice

GearPolice.ChatThrottle = GearPolice.ChatThrottle or {}

local ChatThrottle = GearPolice.ChatThrottle
local ChatPrefix = "GearPolice"
local DefaultPriority = "NORMAL"
local MaxChatMessageLength = 255

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

local function SplitMessage(message)
    local chunks = {}
    if type(message) ~= "string" or message == "" then
        return chunks
    end

    local remainingMessage = message
    while #remainingMessage > MaxChatMessageLength do
        local splitAt

        for index = MaxChatMessageLength, 1, -1 do
            if remainingMessage:sub(index, index) == " " then
                splitAt = index - 1
                break
            end
        end

        if not splitAt or splitAt <= 0 then
            splitAt = MaxChatMessageLength
        end

        table.insert(chunks, remainingMessage:sub(1, splitAt))
        remainingMessage = remainingMessage:sub(splitAt + 1)

        while remainingMessage:sub(1, 1) == " " do
            remainingMessage = remainingMessage:sub(2)
        end
    end

    if remainingMessage ~= "" then
        table.insert(chunks, remainingMessage)
    end

    return chunks
end

local function TryThrottledSend(message, chatType, destination, priority, queueName)
    if not ChatThrottleLib or type(ChatThrottleLib.SendChatMessage) ~= "function" then
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

function ChatThrottle:GetMaxMessageLength()
    return MaxChatMessageLength
end

function ChatThrottle:GetMessageChunks(message)
    return SplitMessage(message)
end

function ChatThrottle:Send(message, chatType, destination, priority, queueName)
    if type(message) ~= "string" or message == "" then
        return false
    end

    chatType = chatType or "SAY"
    priority = IsValidPriority(priority) and priority or DefaultPriority

    local resolvedQueueName = BuildQueueName(chatType, destination, queueName)
    local sentAnyMessage = false

    for _, messageChunk in ipairs(SplitMessage(message)) do
        sentAnyMessage = true
        if not TryThrottledSend(messageChunk, chatType, destination, priority, resolvedQueueName) then
            SendChatMessage(messageChunk, chatType, nil, destination)
        end
    end

    return sentAnyMessage
end
