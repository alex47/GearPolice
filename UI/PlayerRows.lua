local AceGUI = LibStub("AceGUI-3.0")
local GearPolice = GearPolice

local UI = GearPolice.UI

UI.PlayerRows = UI.PlayerRows or {}

local PlayerRows = UI.PlayerRows

function UI:UpdatePlayerStatusIcon(playerGuid, status)
    if not self.playerUIElements then return end

    local playerUI = self.playerUIElements[playerGuid]
    if not playerUI then return end

    playerUI.statusIcon:SetImage(self:GetStatusTexture(status))
end

local function NeedsRebuild(ui, rows)
    for playerGuid in pairs(ui.playerUIElements) do
        if not GearPolice.db.global.PlayerGearInfo[playerGuid] then
            return true
        end
    end

    local playerOrder = ui.playerOrder or {}
    if #playerOrder ~= #rows then
        return true
    end

    for index, row in ipairs(rows) do
        if playerOrder[index] ~= row.playerGuid then
            return true
        end
    end

    return false
end

local function CreatePlayerRow(scrollContainer)
    local playerContainer = AceGUI:Create("SimpleGroup")
    playerContainer:SetFullWidth(true)
    playerContainer:SetLayout("Flow")
    playerContainer:SetHeight(UI.PlayerContainerElementSize)

    local reportButton = AceGUI:Create("Icon")
    reportButton:SetImage("Interface\\COMMON\\VOICECHAT-SPEAKER")
    reportButton:SetImageSize(UI.IconSize, UI.IconSize)
    reportButton:SetWidth(UI.PlayerContainerElementSize)
    reportButton:SetHeight(UI.PlayerContainerElementSize)
    playerContainer:AddChild(reportButton)

    local statusIcon = AceGUI:Create("Icon")
    statusIcon:SetImageSize(UI.IconSize, UI.IconSize)
    statusIcon:SetWidth(UI.PlayerContainerElementSize)
    statusIcon:SetHeight(UI.PlayerContainerElementSize)
    statusIcon:SetImage("Interface\\COMMON\\Indicator-Yellow")
    playerContainer:AddChild(statusIcon)

    local playerNameLabel = AceGUI:Create("Label")
    playerNameLabel:SetWidth(100)
    playerNameLabel:SetHeight(UI.PlayerContainerElementSize)
    playerNameLabel:SetJustifyV("MIDDLE")
    playerContainer:AddChild(playerNameLabel)

    local itemIconsContainer = AceGUI:Create("SimpleGroup")
    itemIconsContainer:SetLayout("Flow")
    itemIconsContainer:SetWidth(500)
    itemIconsContainer:SetHeight(UI.PlayerContainerElementSize)
    playerContainer:AddChild(itemIconsContainer)

    scrollContainer:AddChild(playerContainer)

    return {
        playerContainer = playerContainer,
        reportButton = reportButton,
        statusIcon = statusIcon,
        playerNameLabel = playerNameLabel,
        itemIconsContainer = itemIconsContainer,
    }
end

local function RenderEmptySlot(ui, itemIconsContainer)
    local emptyIcon = ui:CreateEquipmentSlotIcon()
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
end

local function RenderItemSlot(ui, itemIconsContainer, slot)
    local itemIcon = ui:CreateEquipmentSlotIcon()
    itemIcon:SetImage(slot.texture)
    itemIcon:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
        GameTooltip:SetHyperlink(slot.itemLink)
        if type(slot.problems) == "table" and #slot.problems > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("GearPolice:", 1, 0.82, 0, true)
            for _, problem in ipairs(slot.problems) do
                GameTooltip:AddLine(" - " .. problem.message, 1, 0.25, 0.25, true)
            end
        end
        GameTooltip:Show()
    end)
    itemIcon:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)
    itemIcon:SetProblematic(slot.isProblematic)
    itemIconsContainer:AddChild(itemIcon)
end

local function RenderPendingSlot(ui, itemIconsContainer, slot)
    local placeholderIcon = ui:CreateEquipmentSlotIcon()
    placeholderIcon:SetImage(slot.texture)
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

local function RenderSlot(ui, itemIconsContainer, slot)
    if slot.state == "empty" then
        RenderEmptySlot(ui, itemIconsContainer)
    elseif slot.state == "item" then
        RenderItemSlot(ui, itemIconsContainer, slot)
    else
        RenderPendingSlot(ui, itemIconsContainer, slot)
    end
end

local function UpdatePlayerRow(ui, playerUI, row)
    playerUI.reportButton:SetCallback("OnClick", function()
        GearPolice.Reporting:ReportProblematicItems(row.playerInfo)
    end)

    GearPolice.Debug:Message("playerInfo.CheckStatus: " .. (row.checkStatus or "nil"))
    playerUI.statusIcon:SetImage(row.statusTexture)

    if row.hasProblems then
        playerUI.playerNameLabel:SetText("|cffFF0000" .. row.playerName .. "|r")
    else
        playerUI.playerNameLabel:SetText("|cffFFFFFF" .. row.playerName .. "|r")
    end

    local itemIconsContainer = playerUI.itemIconsContainer
    itemIconsContainer:ReleaseChildren()

    for _, slot in ipairs(row.slots) do
        RenderSlot(ui, itemIconsContainer, slot)
    end
end

function PlayerRows.Render(ui, scrollContainer, rows)
    ui.playerUIElements = ui.playerUIElements or {}

    if NeedsRebuild(ui, rows) then
        scrollContainer:ReleaseChildren()
        ui.playerUIElements = {}
    end

    ui.playerOrder = {}
    for _, row in ipairs(rows) do
        table.insert(ui.playerOrder, row.playerGuid)

        local playerUI = ui.playerUIElements[row.playerGuid]
        if not playerUI then
            playerUI = CreatePlayerRow(scrollContainer)
            ui.playerUIElements[row.playerGuid] = playerUI
        end

        UpdatePlayerRow(ui, playerUI, row)
    end
end

function UI:UpdateUI()
    if not self.uiFrame or not self.uiFrame:IsVisible() then
        return
    end

    local rows = self.ViewModel.BuildRows()
    self.PlayerRows.Render(self, self.uiFrame.scrollContainer, rows)
    self.uiFrame:DoLayout()
end
