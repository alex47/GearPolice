GearPolice = LibStub("AceAddon-3.0"):NewAddon("GearPolice", "AceConsole-3.0", "AceEvent-3.0")

GearPolice:RegisterChatCommand("gearpolice", "HandleSlashCommands")

GearPolice.scanQueue = {}
GearPolice.isScanning = false
GearPolice.scanInterval = 2  -- Time between scans in seconds

function GearPolice:OnInitialize()
    GearPolice:Print("Addon loaded!")

    GearPolice.db = LibStub("AceDB-3.0"):New("GearPoliceDB")

    if type(GearPolice.db.global.PlayerGearInfo) ~= "table" then 
        GearPolice.db.global.PlayerGearInfo = {} 
    end

    -- Initialize PublicShamingEnabled if it's not set
    if type(GearPolice.db.global.PublicShamingEnabled) ~= "boolean" then
        GearPolice.db.global.PublicShamingEnabled = false
    end

    -- Initialize DebugEnabled if it's not set
    if type(GearPolice.db.global.DebugEnabled) ~= "boolean" then
        GearPolice.db.global.DebugEnabled = false
    end
end

function GearPolice:ProcessScanQueue()
    if GearPolice.isScanning or #GearPolice.scanQueue == 0 then
        return
    end

    GearPolice.isScanning = true
    local playerGuid = table.remove(GearPolice.scanQueue, 1)
    local unitId = GearPolice.Helper:GetUnitIdOfPlayerGuid(playerGuid)
    local playerInfo = GearPolice.db.global.PlayerGearInfo[playerGuid]

    if unitId and playerInfo and playerInfo.CheckStatus ~= "Successful" then
        GearPolice:StartInspectionOfUnit(unitId)

        if GearPolice.db.global.DebugEnabled then
            local playerName = UnitName(unitId) or "Unknown Player"
            GearPolice.Debug:Message("Scanning player: " .. playerName)
        end
    else
        -- If unitId is not available, we can't proceed
        GearPolice.isScanning = false
        C_Timer.After(GearPolice.scanInterval, function()
            GearPolice:AddToScanQueue(playerGuid)
            GearPolice:ProcessScanQueue()
        end)
    end
end

function GearPolice:AddToScanQueue(playerGuid)
    if not tContains(GearPolice.scanQueue, playerGuid) then
        table.insert(GearPolice.scanQueue, playerGuid)
    end
end

function GearPolice:UpdatePlayerGearInfoWithGroupMembers()
    local groupType, maxMembers
    if IsInRaid() then
        groupType = "raid"
        maxMembers = 40
    elseif IsInGroup() then
        groupType = "party"
        maxMembers = 4
    else
        return
    end

    for i = 1, maxMembers do
        local unitId = groupType .. i

        if UnitExists(unitId) then
            GearPolice:ProcessGroupMember(unitId)
        end
    end
end

function GearPolice:ProcessGroupMember(unitId)
    if not UnitExists(unitId) then
        return
    end

    local playerGuid = UnitGUID(unitId)
    local playerName = UnitName(unitId)

    if not playerName or playerName == "Unknown" then
        -- Delay and retry this player
        C_Timer.After(1, function()
            GearPolice:ProcessGroupMember(unitId)
        end)
        return
    end

    local isNewPlayer = false

    if GearPolice.db.global.PlayerGearInfo[playerGuid] == nil then
        GearPolice:SetPlayerGuidToDefaultInPlayerGearInfo(playerGuid)
        isNewPlayer = true
    else
        -- Clear previous data for rejoining players
        GearPolice:ResetPlayerGearInfo(playerGuid)
    end

    -- Add to scan queue
    GearPolice:AddToScanQueue(playerGuid)

    -- Update the UI if this is a new player
    if isNewPlayer then
        GearPolice.UI:UpdateUI()
    end
end

function GearPolice:ResetPlayerGearInfo(playerGuid)
    if GearPolice.db.global.PlayerGearInfo[playerGuid] then
        GearPolice.db.global.PlayerGearInfo[playerGuid].CheckRequested = true
        GearPolice.db.global.PlayerGearInfo[playerGuid].CheckStatus = "InProgress"
        GearPolice.db.global.PlayerGearInfo[playerGuid].ProblematicItems = {}
        GearPolice.db.global.PlayerGearInfo[playerGuid].LastScanTime = 0
    end
end

function GearPolice:SetPlayerGuidToDefaultInPlayerGearInfo(playerGuid)
    if not playerGuid then
        return
    end

    local _, _, _, _, _, playerName = GetPlayerInfoByGUID(playerGuid)

    GearPolice.db.global.PlayerGearInfo[playerGuid] = {
        ["PlayerName"] = playerName or "Unknown",
        ["PlayerGuid"] = playerGuid,
        ["CheckRequested"] = true,
        ["CheckStatus"] = "InProgress",
        ["ProblematicItems"] = {},
        ["LastScanTime"] = 0
    }
end

function GearPolice:StartInspectionOfUnit(unitId)
    if not UnitExists(unitId) then
        GearPolice.isScanning = false
        return
    end

    local playerGuid = UnitGUID(unitId)

    -- Update the status icon to scanning
    local playerUI = GearPolice.UI.playerUIElements[playerGuid]
    if playerUI then
        playerUI.statusIcon:SetImage("Interface\\COMMON\\Indicator-Yellow")
        GearPolice.UI.uiFrame:DoLayout()
    end

    if CanInspect(unitId) then
        NotifyInspect(unitId)
    else
        -- Can't inspect now, retry later
        if GearPolice.db.global.DebugEnabled then
            local playerName = UnitName(unitId) or "Unknown Player"
            GearPolice.Debug:Message("Cannot inspect " .. playerName .. ", retrying later.")
        end
        GearPolice.isScanning = false
        C_Timer.After(GearPolice.scanInterval, function()
            local playerGuid = UnitGUID(unitId)
            if playerGuid then
                GearPolice:AddToScanQueue(playerGuid)
                GearPolice:ProcessScanQueue()
            end
        end)
    end
end

function GearPolice:StartGearPolicingOfGroup()
    GearPolice:UpdatePlayerGearInfoWithGroupMembers()
    GearPolice:ProcessScanQueue()
end

function GearPolice:StartGearPolicingOfTarget()
    local targetGuid = UnitGUID("target")
    if targetGuid then
        GearPolice:ProcessGroupMember("target")
        GearPolice:ProcessScanQueue()
        GearPolice.UI:UpdateUI()  -- Update the UI to add the target player
    end
end

function GearPolice:OnInspectReady(eventName, playerGuid)
    if not playerGuid then
        return
    end

    local playerInfo = GearPolice.db.global.PlayerGearInfo[playerGuid]

    if not playerInfo or not playerInfo.CheckRequested then
        GearPolice.isScanning = false
        return
    end

    playerInfo.CheckStatus = "InProgress"
    GearPolice.UI:UpdateUI()
    
    GearPolice.Inspection:CheckUnit(playerInfo)

    playerInfo.CheckRequested = false
    playerInfo.CheckStatus = "Successful"
    playerInfo.LastScanTime = time()

    GearPolice.Debug:Message("Scan completed for: " .. playerInfo.PlayerName)

    -- Update the status icon and item icons directly
    local playerUI = GearPolice.UI.playerUIElements[playerGuid]
    if playerUI then
        -- Update the status icon to checkmark
        playerUI.statusIcon:SetImage("Interface\\RaidFrame\\ReadyCheck-Ready")

        -- Update item icons
        local itemIconsContainer = playerUI.itemIconsContainer
        itemIconsContainer:ReleaseChildren()
        for itemLink, _ in pairs(playerInfo.ProblematicItems or {}) do
            GearPolice.UI:AddItemIcon(itemIconsContainer, itemLink)
        end

        -- Force layout update
        GearPolice.UI.uiFrame:DoLayout()
    end

    GearPolice.isScanning = false
    -- Schedule next scan
    C_Timer.After(GearPolice.scanInterval, function()
        GearPolice:ProcessScanQueue()
    end)
end

-- Keep INSPECT_READY event
GearPolice:RegisterEvent("INSPECT_READY", "OnInspectReady")

-- Slash command

function GearPolice:HandleSlashCommands(msg, editbox)
    if (msg == "target") then
        GearPolice:StartGearPolicingOfTarget()
    elseif (msg == "showui") then
        GearPolice.UI:ShowUI()
    elseif (msg == "debug") then
        GearPolice.db.global.DebugEnabled = not GearPolice.db.global.DebugEnabled
        GearPolice:Print("Debug mode " .. (GearPolice.db.global.DebugEnabled and "enabled" or "disabled") .. ".")
    else
        -- Start scanning group when no argument is provided
        GearPolice:StartGearPolicingOfGroup()
    end
end
