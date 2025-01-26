local AceGUI = LibStub("AceGUI-3.0")
local GearPolice = GearPolice

GearPolice.UI = GearPolice.UI or {}
local UI = GearPolice.UI

local IconSize = 16  -- Set the icon size here
local PlayerContainerElementSize = 24


function UI:AddItemIcon(container, itemLink)
    local itemIcon = AceGUI:Create("Icon")
    local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
    itemIcon:SetImage(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
    itemIcon:SetImageSize(IconSize, IconSize)
    itemIcon:SetWidth(PlayerContainerElementSize)
    itemIcon:SetHeight(PlayerContainerElementSize)

    itemIcon:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:Show()
    end)

    itemIcon:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)

    container:AddChild(itemIcon)
end

function UI:HorizontalLayout(container)
    local width = container.frame.width or container.width or 0
    local spacing = 10
    local usedWidth = 0

    for _, child in ipairs(container.children) do
        local childFrame = child.frame
        childFrame:ClearAllPoints()
        childFrame:SetPoint("TOPLEFT", container.frame, "TOPLEFT", usedWidth, 0)
        usedWidth = usedWidth + childFrame:GetWidth() + spacing
    end
end

function UI:LayoutPlayerContainer(playerContainer, playerNameLabel, gemsContainer, enchantContainer)
    playerNameLabel.frame:ClearAllPoints()
    playerNameLabel.frame:SetPoint("TOPLEFT", playerContainer.frame, "TOPLEFT", 0, 0)

    gemsContainer.frame:ClearAllPoints()
    gemsContainer.frame:SetPoint("TOPLEFT", playerNameLabel.frame, "TOPRIGHT", 10, 0)

    enchantContainer.frame:ClearAllPoints()
    enchantContainer.frame:SetPoint("TOPLEFT", gemsContainer.frame, "TOPRIGHT", 10, 0)
end

function UI:UpdateUI()
    if not self.uiFrame or not self.uiFrame:IsVisible() then
        return  -- UI is not created or not visible
    end

    local scrollContainer = self.uiFrame.scrollContainer

    -- Remove UI elements for players no longer in PlayerGearInfo
    for playerGuid, playerUI in pairs(self.playerUIElements) do
        if not GearPolice.db.global.PlayerGearInfo[playerGuid] then
            -- Remove UI elements
            scrollContainer:RemoveChild(playerUI.playerContainer)
            self.playerUIElements[playerGuid] = nil
        end
    end

    -- Update or create UI elements for each player
    for playerGuid, playerInfo in pairs(GearPolice.db.global.PlayerGearInfo) do
        local playerUI = self.playerUIElements[playerGuid]

        if not playerUI then
            -- Create UI elements for this player
            local playerContainer = AceGUI:Create("SimpleGroup")
            playerContainer:SetFullWidth(true)
            playerContainer:SetLayout("Flow")
            playerContainer:SetHeight(PlayerContainerElementSize)

            -- Create the Report button
            local reportButton = AceGUI:Create("Icon")
            reportButton:SetImage("Interface\\COMMON\\VOICECHAT-SPEAKER")
            reportButton:SetImageSize(IconSize, IconSize)
            reportButton:SetWidth(PlayerContainerElementSize)
            reportButton:SetHeight(PlayerContainerElementSize)
            reportButton:SetCallback("OnClick", function(widget)
                GearPolice.Reporting:ReportProblematicItems(playerInfo)
            end)
            playerContainer:AddChild(reportButton)

            -- Create the status icon
            local statusIcon = AceGUI:Create("Icon")
            statusIcon:SetImageSize(IconSize, IconSize)
            statusIcon:SetWidth(PlayerContainerElementSize)
            statusIcon:SetHeight(PlayerContainerElementSize)
            statusIcon:SetImage("Interface\\COMMON\\Indicator-Yellow")  -- Default icon
            playerContainer:AddChild(statusIcon)

            -- Create the player name label
            local playerNameLabel = AceGUI:Create("Label")
            playerNameLabel:SetText(playerInfo.PlayerName or "Unknown Player")
            playerNameLabel:SetWidth(100)
            playerNameLabel:SetHeight(PlayerContainerElementSize)
            playerNameLabel.label:SetJustifyV("MIDDLE")  -- Vertically center text
            playerContainer:AddChild(playerNameLabel)

            -- Create item icons container
            local itemIconsContainer = AceGUI:Create("SimpleGroup")
            itemIconsContainer:SetLayout("Flow")
            -- Remove SetFullWidth(true) to prevent wrapping
            -- itemIconsContainer:SetFullWidth(true)
            itemIconsContainer:SetWidth(300)  -- Adjust as needed
            itemIconsContainer:SetHeight(PlayerContainerElementSize)
            playerContainer:AddChild(itemIconsContainer)

            -- Add the playerContainer to the scrollContainer
            scrollContainer:AddChild(playerContainer)

            -- Store references to the UI elements
            self.playerUIElements[playerGuid] = {
                playerContainer = playerContainer,
                reportButton = reportButton,
                statusIcon = statusIcon,
                playerNameLabel = playerNameLabel,
                itemIconsContainer = itemIconsContainer,
            }
            playerUI = self.playerUIElements[playerGuid]
        end

        -- Update the status icon
        local statusIcon = playerUI.statusIcon

        GearPolice.Debug:Message("playerInfo.CheckStatus: " .. playerInfo.CheckStatus)

        if playerInfo.CheckStatus == "InProgress" then
            statusIcon:SetImage("Interface\\COMMON\\Indicator-Yellow")
        elseif playerInfo.CheckStatus == "Successful" then
            statusIcon:SetImage("Interface\\RaidFrame\\ReadyCheck-Ready")
        else
            statusIcon:SetImage(nil)
        end

        -- Update the player name label in case it has changed
        local playerNameLabel = playerUI.playerNameLabel
        playerNameLabel:SetText(playerInfo.PlayerName or "Unknown Player")

        -- Update item icons
        local itemIconsContainer = playerUI.itemIconsContainer
        itemIconsContainer:ReleaseChildren()
        if playerInfo.CheckStatus == "Successful" then
            for itemLink, _ in pairs(playerInfo.ProblematicItems or {}) do
                self:AddItemIcon(itemIconsContainer, itemLink)
            end
        end
    end

    -- Force layout update
    self.uiFrame:DoLayout()
end

function UI:ShowUI()
    -- Release the existing frame if it exists
    if self.uiFrame then
        AceGUI:Release(self.uiFrame)
        self.uiFrame = nil
        self.playerUIElements = nil  -- Clear the cached UI elements
    end

    -- Create a new frame
    self.uiFrame = AceGUI:Create("Frame")
    self.uiFrame:SetTitle("Gear Police")
    self.uiFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        self.uiFrame = nil
        self.playerUIElements = nil  -- Clear the cached UI elements
    end)
    self.uiFrame:SetLayout("Flow")
    self.uiFrame:SetWidth(640)  -- Increased from 640
    self.uiFrame:SetHeight(480)

    -- Initialize the player UI elements table
    self.playerUIElements = {}

    local clearButton = AceGUI:Create("Button")
    clearButton:SetText("Clear")
    clearButton:SetWidth(100)
    clearButton:SetHeight(24)
    clearButton:SetCallback("OnClick", function()
        GearPolice.db.global.PlayerGearInfo = {}
        GearPolice.scanQueue = {}
        GearPolice.isScanning = false
    
        -- Clear the cached UI elements and release the UI children
        self.playerUIElements = {}
        self.uiFrame.scrollContainer:ReleaseChildren()
    
        -- Update the UI
        self:UpdateUI()
    end)
    
    self.uiFrame:AddChild(clearButton)

    local refreshButton = AceGUI:Create("Button")
    refreshButton:SetText("Refresh")
    refreshButton:SetWidth(100)
    refreshButton:SetHeight(24)
    refreshButton:SetCallback("OnClick", function()
        GearPolice.db.global.PlayerGearInfo = {}
        GearPolice.scanQueue = {}
        GearPolice.isScanning = false
        self:UpdateUI()
        GearPolice:StartGearPolicingOfGroup()
    end)
    self.uiFrame:AddChild(refreshButton)

    local targetButton = AceGUI:Create("Button")
    targetButton:SetText("Target")
    targetButton:SetWidth(100)
    targetButton:SetHeight(24)
    targetButton:SetCallback("OnClick", function()
        GearPolice:StartGearPolicingOfTarget()
    end)
    self.uiFrame:AddChild(targetButton)

    -- Create the Public Shaming checkbox
    local publicShamingCheckbox = AceGUI:Create("CheckBox")
    publicShamingCheckbox:SetLabel("Public Shaming")
    publicShamingCheckbox:SetWidth(120)
    publicShamingCheckbox:SetValue(GearPolice.db.global.PublicShamingEnabled)
    publicShamingCheckbox:SetCallback("OnValueChanged", function(widget, event, value)
        GearPolice.db.global.PublicShamingEnabled = value
        if value then
            SendChatMessage("{Square} GearPolice {Cross} Public Shaming mode: Activated", IsInRaid() and "RAID" or "PARTY")
        end
    end)
    self.uiFrame:AddChild(publicShamingCheckbox)

    -- Create and set up the scroll container
    self.uiFrame.scrollContainer = AceGUI:Create("ScrollFrame")
    self.uiFrame.scrollContainer:SetFullWidth(true)
    self.uiFrame.scrollContainer:SetLayout("List")
    self.uiFrame:AddChild(self.uiFrame.scrollContainer)

    -- Populate the UI
    self:UpdateUI()
end
