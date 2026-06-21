local AceGUI = LibStub("AceGUI-3.0")
local GearPolice = GearPolice

GearPolice.UI = GearPolice.UI or {}
local UI = GearPolice.UI

local IconSize = 16  -- Set the icon size here
local PlayerContainerElementSize = 24

local ItemIconWidgetType = "GearPoliceItemIcon"
local ItemIconWidgetVersion = 1

local function ItemIcon_OnEnter(frame)
    frame.obj:Fire("OnEnter")
end

local function ItemIcon_OnLeave(frame)
    frame.obj:Fire("OnLeave")
end

local function ItemIcon_OnClick(frame, button)
    frame.obj:Fire("OnClick", button)
end

local itemIconMethods = {
    OnAcquire = function(self)
        self:SetWidth(PlayerContainerElementSize)
        self:SetHeight(PlayerContainerElementSize)
        self:SetImage(nil)
        self:SetImageSize(IconSize, IconSize)
        self:SetProblematic(false)
        self.image:SetVertexColor(1, 1, 1, 1)
        self.frame:Enable()
    end,

    OnRelease = function(self)
        self:SetProblematic(false)
        self:SetImage(nil)
    end,

    SetImage = function(self, path, ...)
        self.image:SetTexture(path)

        if self.image:GetTexture() then
            local argCount = select("#", ...)
            if argCount == 4 or argCount == 8 then
                self.image:SetTexCoord(...)
            else
                self.image:SetTexCoord(0, 1, 0, 1)
            end
        end
    end,

    SetImageSize = function(self, width, height)
        self.image:SetWidth(width)
        self.image:SetHeight(height)
    end,

    SetProblematic = function(self, isProblematic)
        if not self.frame.SetBackdrop then
            return
        end

        self.frame:SetBackdrop(nil)

        if isProblematic then
            self.frame:SetBackdrop({
                bgFile = nil,
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false,
                edgeSize = 16,
            })
            if self.frame.SetBackdropBorderColor then
                self.frame:SetBackdropBorderColor(1, 0, 0, 1)
            end
        end
    end,
}

local function CreateItemIconWidget()
    local backdropTemplate = _G.BackdropTemplateMixin and "BackdropTemplate" or nil
    local frame = CreateFrame("Button", nil, UIParent, backdropTemplate)
    frame:Hide()
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", ItemIcon_OnEnter)
    frame:SetScript("OnLeave", ItemIcon_OnLeave)
    frame:SetScript("OnClick", ItemIcon_OnClick)

    local image = frame:CreateTexture(nil, "BACKGROUND")
    image:SetPoint("CENTER")

    local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(image)
    highlight:SetTexture(136580) -- Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight
    highlight:SetTexCoord(0, 1, 0.23, 0.77)
    highlight:SetBlendMode("ADD")

    local widget = {
        image = image,
        frame = frame,
        type = ItemIconWidgetType,
    }

    for methodName, method in pairs(itemIconMethods) do
        widget[methodName] = method
    end

    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(ItemIconWidgetType, CreateItemIconWidget, ItemIconWidgetVersion)

local function CreateEquipmentSlotIcon()
    local icon = AceGUI:Create(ItemIconWidgetType)
    icon:SetImageSize(IconSize, IconSize)
    icon:SetWidth(PlayerContainerElementSize)
    icon:SetHeight(PlayerContainerElementSize)
    icon:SetProblematic(false)

    return icon
end

function UI:UpdatePlayerStatusIcon(playerGuid, status)
    if not self.playerUIElements then return end

    local playerUI = self.playerUIElements[playerGuid]
    if not playerUI then return end

    local statusIcon = playerUI.statusIcon
    local texturePaths = {
        scanning = "Interface\\COMMON\\Indicator-Yellow",
        success = "Interface\\RaidFrame\\ReadyCheck-Ready",
        failed = "Interface\\RaidFrame\\ReadyCheck-NotReady",
        temporary_failed = "Interface\\RaidFrame\\ReadyCheck-Waiting"
    }

    statusIcon:SetImage(texturePaths[status] or nil)
end

function UI:UpdateUI()
    if not self.uiFrame or not self.uiFrame:IsVisible() then
        return  -- UI is not created or not visible.
    end

    local scrollContainer = self.uiFrame.scrollContainer
    self.playerUIElements = self.playerUIElements or {}
    local orderedPlayerGuids = GearPolice:GetOrderedPlayerGuids()

    -- AceGUI has no supported single-child removal API; rebuild if the row cache is stale.
    local needsRebuild = false
    for playerGuid in pairs(self.playerUIElements) do
        if not GearPolice.db.global.PlayerGearInfo[playerGuid] then
            needsRebuild = true
            break
        end
    end

    if not needsRebuild then
        local playerOrder = self.playerOrder or {}
        if #playerOrder ~= #orderedPlayerGuids then
            needsRebuild = true
        else
            for index, playerGuid in ipairs(orderedPlayerGuids) do
                if playerOrder[index] ~= playerGuid then
                    needsRebuild = true
                    break
                end
            end
        end
    end

    if needsRebuild then
        scrollContainer:ReleaseChildren()
        self.playerUIElements = {}
    end

    self.playerOrder = {}
    local slotOrder = GearPolice.Helper:GetInventorySlotNames()

    for _, playerGuid in ipairs(orderedPlayerGuids) do
        local playerInfo = GearPolice.db.global.PlayerGearInfo[playerGuid]
        table.insert(self.playerOrder, playerGuid)
        local playerUI = self.playerUIElements[playerGuid]

        if not playerUI then
            -- Create UI elements for this player.
            local playerContainer = AceGUI:Create("SimpleGroup")
            playerContainer:SetFullWidth(true)
            playerContainer:SetLayout("Flow")
            playerContainer:SetHeight(PlayerContainerElementSize)

            local reportButton = AceGUI:Create("Icon")
            reportButton:SetImage("Interface\\COMMON\\VOICECHAT-SPEAKER")
            reportButton:SetImageSize(IconSize, IconSize)
            reportButton:SetWidth(PlayerContainerElementSize)
            reportButton:SetHeight(PlayerContainerElementSize)
            reportButton:SetCallback("OnClick", function()
                GearPolice.Reporting:ReportProblematicItems(playerInfo)
            end)
            playerContainer:AddChild(reportButton)

            local statusIcon = AceGUI:Create("Icon")
            statusIcon:SetImageSize(IconSize, IconSize)
            statusIcon:SetWidth(PlayerContainerElementSize)
            statusIcon:SetHeight(PlayerContainerElementSize)
            statusIcon:SetImage("Interface\\COMMON\\Indicator-Yellow")
            playerContainer:AddChild(statusIcon)

            local playerNameLabel = AceGUI:Create("Label")
            playerNameLabel:SetWidth(100)
            playerNameLabel:SetHeight(PlayerContainerElementSize)
            playerNameLabel:SetJustifyV("MIDDLE")
            playerContainer:AddChild(playerNameLabel)

            local itemIconsContainer = AceGUI:Create("SimpleGroup")
            itemIconsContainer:SetLayout("Flow")
            itemIconsContainer:SetWidth(500)
            itemIconsContainer:SetHeight(PlayerContainerElementSize)
            playerContainer:AddChild(itemIconsContainer)

            scrollContainer:AddChild(playerContainer)

            self.playerUIElements[playerGuid] = {
                playerContainer = playerContainer,
                reportButton = reportButton,
                statusIcon = statusIcon,
                playerNameLabel = playerNameLabel,
                itemIconsContainer = itemIconsContainer,
            }
            playerUI = self.playerUIElements[playerGuid]
        end

        -- Update status icon.
        local statusIcon = playerUI.statusIcon
        GearPolice.Debug:Message("playerInfo.CheckStatus: " .. playerInfo.CheckStatus)
        if playerInfo.CheckStatus == "InProgress" then
            statusIcon:SetImage("Interface\\COMMON\\Indicator-Yellow")
        elseif playerInfo.CheckStatus == "Successful" then
            statusIcon:SetImage("Interface\\RaidFrame\\ReadyCheck-Ready")
        elseif playerInfo.CheckStatus == "Partial" then
            statusIcon:SetImage("Interface\\RaidFrame\\ReadyCheck-Waiting")
        elseif playerInfo.CheckStatus == "Failed" then
            statusIcon:SetImage("Interface\\RaidFrame\\ReadyCheck-NotReady")
        elseif playerInfo.CheckStatus == "TemporaryFailed" then
            statusIcon:SetImage("Interface\\RaidFrame\\ReadyCheck-Waiting")
        else
            statusIcon:SetImage(nil)
        end

        -- Update player name label.
        local playerNameLabel = playerUI.playerNameLabel
        if playerInfo.ProblematicItems and next(playerInfo.ProblematicItems) then
            playerNameLabel:SetText("|cffFF0000" .. (playerInfo.PlayerName or "Unknown Player") .. "|r")
        else
            playerNameLabel:SetText("|cffFFFFFF" .. (playerInfo.PlayerName or "Unknown Player") .. "|r")
        end

        local itemIconsContainer = playerUI.itemIconsContainer
        itemIconsContainer:ReleaseChildren()

        -- Loop over each equipment slot.
        for _, slotName in ipairs(slotOrder) do
            local itemLink = playerInfo.EquippedItems and playerInfo.EquippedItems[slotName]
            if itemLink == GearPolice.InventorySlotEmpty then
                local emptyIcon = CreateEquipmentSlotIcon()
                emptyIcon:SetImage(nil)
                emptyIcon:SetCallback("OnEnter", function(widget)
                    GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
                    GameTooltip:SetText("Empty slot", 1, 1, 1)
                    GameTooltip:Show()
                end)
                emptyIcon:SetCallback("OnLeave", function()
                    GameTooltip:Hide()
                end)
                itemIconsContainer:AddChild(emptyIcon)
            elseif itemLink and itemLink ~= GearPolice.InventorySlotPending then
                -- Create an icon widget.
                local itemIcon = CreateEquipmentSlotIcon()
                local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
                itemIcon:SetImage(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
                itemIcon:SetCallback("OnEnter", function(widget)
                    GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
                    GameTooltip:SetHyperlink(itemLink)
                    GameTooltip:Show()
                end)
                itemIcon:SetCallback("OnLeave", function()
                    GameTooltip:Hide()
                end)
                -- If this item is marked problematic, highlight it.
                itemIcon:SetProblematic(playerInfo.ProblematicItems and playerInfo.ProblematicItems[itemLink])
                itemIconsContainer:AddChild(itemIcon)
            else
                -- Show placeholder icon.
                local placeholderIcon = CreateEquipmentSlotIcon()
                placeholderIcon:SetImage("Interface\\Icons\\INV_Misc_QuestionMark")
                placeholderIcon:SetCallback("OnEnter", function(widget)
                    GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
                    GameTooltip:SetText("Scanning...", 1, 1, 1)
                    GameTooltip:Show()
                end)
                placeholderIcon:SetCallback("OnLeave", function()
                    GameTooltip:Hide()
                end)
                itemIconsContainer:AddChild(placeholderIcon)
            end
        end
    end

    self.uiFrame:DoLayout()
end

function UI:ShowUI()
    -- Release the existing frame if it exists
    if self.uiFrame then
        AceGUI:Release(self.uiFrame)
        self.uiFrame = nil
        self.playerUIElements = nil  -- Clear the cached UI elements
        self.playerOrder = nil
    end

    -- Create a new frame
    self.uiFrame = AceGUI:Create("Frame")
    self.uiFrame:SetTitle("Gear Police")
    self.uiFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        self.uiFrame = nil
        self.playerUIElements = nil  -- Clear the cached UI elements
        self.playerOrder = nil
    end)
    self.uiFrame:SetLayout("Flow")
    self.uiFrame:SetWidth(800)  -- Increased from 640
    self.uiFrame:SetHeight(480)

    -- Initialize the player UI elements table
    self.playerUIElements = {}
    self.playerOrder = {}

    local clearButton = AceGUI:Create("Button")
    clearButton:SetText("Clear")
    clearButton:SetWidth(100)
    clearButton:SetHeight(24)
    clearButton:SetCallback("OnClick", function()
        GearPolice:ClearAllTrackedPlayers()
    end)

    self.uiFrame:AddChild(clearButton)

    local refreshButton = AceGUI:Create("Button")
    refreshButton:SetText("Refresh")
    refreshButton:SetWidth(100)
    refreshButton:SetHeight(24)
    refreshButton:SetCallback("OnClick", function()
        GearPolice:ClearAllTrackedPlayers()
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

    local reportModeDropdown = AceGUI:Create("Dropdown")
    reportModeDropdown:SetLabel("Report Mode")
    reportModeDropdown:SetWidth(160)
    reportModeDropdown:SetList({
        whisper = "Whisper",
        public = "Public",
        debug = "Debug",
    }, {
        "whisper",
        "public",
        "debug",
    })
    reportModeDropdown:SetValue(GearPolice.db.global.ReportMode)
    reportModeDropdown:SetCallback("OnValueChanged", function(_widget, _event, value)
        GearPolice.db.global.ReportMode = value
    end)
    self.uiFrame:AddChild(reportModeDropdown)

    -- AceGUI ScrollFrames need a Fill-layout parent to size and scroll correctly.
    self.uiFrame.scrollWrapper = AceGUI:Create("SimpleGroup")
    self.uiFrame.scrollWrapper:SetFullWidth(true)
    self.uiFrame.scrollWrapper:SetFullHeight(true)
    self.uiFrame.scrollWrapper:SetLayout("Fill")
    self.uiFrame:AddChild(self.uiFrame.scrollWrapper)

    self.uiFrame.scrollContainer = AceGUI:Create("ScrollFrame")
    self.uiFrame.scrollContainer:SetLayout("List")
    self.uiFrame.scrollWrapper:AddChild(self.uiFrame.scrollContainer)

    -- Populate the UI
    self:UpdateUI()
end
