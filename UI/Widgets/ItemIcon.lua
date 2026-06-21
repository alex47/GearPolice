local AceGUI = LibStub("AceGUI-3.0")
local GearPolice = GearPolice

local UI = GearPolice.UI

local ItemStripWidgetVersion = 1
local CenteredIconWidgetVersion = 1

local function ApplyTextureColor(texture, color)
    if color then
        texture:SetVertexColor(color[1], color[2], color[3], color[4])
    else
        texture:SetVertexColor(1, 1, 1, 1)
    end
end

local function ApplyFrameBackdrop(frame, stateConfig)
    if not frame.SetBackdrop then
        return
    end

    frame:SetBackdrop(nil)

    if not stateConfig or (not stateConfig.borderColor and not stateConfig.backgroundColor) then
        return
    end

    frame:SetBackdrop({
        bgFile = stateConfig.backgroundColor and "Interface\\Buttons\\WHITE8X8" or nil,
        edgeFile = stateConfig.borderColor and "Interface\\Tooltips\\UI-Tooltip-Border" or nil,
        tile = false,
        edgeSize = 12,
        insets = {
            left = 2,
            right = 2,
            top = 2,
            bottom = 2,
        },
    })

    if stateConfig.borderColor and frame.SetBackdropBorderColor then
        local color = stateConfig.borderColor
        frame:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
    end

    if stateConfig.backgroundColor and frame.SetBackdropColor then
        local color = stateConfig.backgroundColor
        frame:SetBackdropColor(color[1], color[2], color[3], color[4])
    end
end

local function SetButtonVisualState(button, state)
    local stateConfig = UI.ItemIconVisualStates[state or "ok"] or UI.ItemIconVisualStates.ok
    ApplyFrameBackdrop(button, stateConfig)
    ApplyTextureColor(button.image, stateConfig and stateConfig.imageColor)
end

local function SetButtonImage(button, texture)
    button.image:SetTexture(texture)

    if button.image:GetTexture() then
        button.image:SetTexCoord(0, 1, 0, 1)
    end
end

local function AddProblemLines(slot)
    if type(slot.problems) ~= "table" or #slot.problems == 0 then
        return
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("GearPolice:", 1, 0.82, 0, true)
    for _, problem in ipairs(slot.problems) do
        GameTooltip:AddLine(" - " .. problem.message, 1, 0.25, 0.25, true)
    end
end

local function ShowSlotTooltip(button)
    local widget = button.obj
    local slot = widget.slots and widget.slots[button.slotIndex]
    if not slot then
        return
    end

    GameTooltip:SetOwner(button, "ANCHOR_TOP")

    if slot.state == "item" and slot.itemLink then
        GameTooltip:SetHyperlink(slot.itemLink)
        AddProblemLines(slot)
    elseif slot.state == "empty" then
        GameTooltip:SetText(slot.slotLabel or "Empty Slot", 1, 1, 1)
        GameTooltip:AddLine("Empty slot", 0.7, 0.7, 0.7, true)
    else
        GameTooltip:SetText(slot.slotLabel or "Equipment Slot", 1, 1, 1)
        GameTooltip:AddLine("Scanning...", 1, 0.82, 0, true)
    end

    GameTooltip:Show()
end

local function SlotButton_OnEnter(button)
    ShowSlotTooltip(button)
end

local function SlotButton_OnLeave()
    GameTooltip:Hide()
end

local function CenteredIcon_OnClick(frame, button)
    frame.obj:Fire("OnClick", button)
    AceGUI:ClearFocus()
end

local function CreateSlotButton(widget, index)
    local backdropTemplate = _G.BackdropTemplateMixin and "BackdropTemplate" or nil
    local button = CreateFrame("Button", nil, widget.frame, backdropTemplate)
    button:SetWidth(UI.EquipmentIconFrameSize)
    button:SetHeight(UI.EquipmentIconFrameSize)
    button:EnableMouse(true)
    button.obj = widget
    button.slotIndex = index
    button:SetScript("OnEnter", SlotButton_OnEnter)
    button:SetScript("OnLeave", SlotButton_OnLeave)

    local image = button:CreateTexture(nil, "BACKGROUND")
    image:SetPoint("CENTER")
    image:SetWidth(UI.IconSize)
    image:SetHeight(UI.IconSize)
    button.image = image

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(image)
    highlight:SetTexture(136580)
    highlight:SetTexCoord(0, 1, 0.23, 0.77)
    highlight:SetBlendMode("ADD")

    return button
end

local function EnsureSlotButtons(widget, slotCount)
    for i = #widget.buttons + 1, slotCount do
        widget.buttons[i] = CreateSlotButton(widget, i)
    end
end

local function PositionSlotButtons(widget, slotCount)
    for i = 1, slotCount do
        local button = widget.buttons[i]
        button:ClearAllPoints()

        if i == 1 then
            button:SetPoint("LEFT", widget.frame, "LEFT", 0, 0)
        else
            button:SetPoint("LEFT", widget.buttons[i - 1], "RIGHT", UI.EquipmentIconSpacing, 0)
        end

        button:Show()
    end

    for i = slotCount + 1, #widget.buttons do
        widget.buttons[i]:Hide()
    end
end

local function RenderSlotButton(button, slot)
    if slot.state == "item" then
        SetButtonImage(button, slot.texture)
        SetButtonVisualState(button, slot.isProblematic and "problem" or "ok")
    elseif slot.state == "empty" then
        SetButtonImage(button, nil)
        SetButtonVisualState(button, "empty")
    else
        SetButtonImage(button, slot.texture)
        SetButtonVisualState(button, "pending")
    end
end

local itemStripMethods = {
    OnAcquire = function(self)
        self.slots = {}
        self:SetHeight(UI.PlayerContainerElementSize)
        self:SetWidth(UI:GetEquipmentIconStripWidth(0))
    end,

    OnRelease = function(self)
        self.slots = {}

        for _, button in ipairs(self.buttons) do
            button:Hide()
            SetButtonImage(button, nil)
            SetButtonVisualState(button, "ok")
        end
    end,

    SetSlots = function(self, slots)
        self.slots = slots or {}

        local slotCount = #self.slots
        self:SetWidth(UI:GetEquipmentIconStripWidth(slotCount))
        self:SetHeight(UI.PlayerContainerElementSize)

        EnsureSlotButtons(self, slotCount)
        PositionSlotButtons(self, slotCount)

        for i, slot in ipairs(self.slots) do
            RenderSlotButton(self.buttons[i], slot)
        end
    end,
}

local function CreateItemStripWidget()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    frame:SetHeight(UI.PlayerContainerElementSize)
    frame:EnableMouse(false)

    local widget = {
        buttons = {},
        slots = {},
        frame = frame,
        type = UI.ItemStripWidgetType,
    }

    for methodName, method in pairs(itemStripMethods) do
        widget[methodName] = method
    end

    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(UI.ItemStripWidgetType, CreateItemStripWidget, ItemStripWidgetVersion)

function UI:CreateEquipmentIconStrip()
    local strip = AceGUI:Create(self.ItemStripWidgetType)
    strip:SetHeight(self.PlayerContainerElementSize)
    strip:SetWidth(self:GetEquipmentIconStripWidth(#GearPolice.Helper:GetInventorySlotNames()))

    return strip
end

local centeredIconMethods = {
    OnAcquire = function(self)
        self:SetWidth(UI.PlayerContainerElementSize)
        self:SetHeight(UI.PlayerContainerElementSize)
        self:SetImage(nil)
        self.frame:EnableMouse(true)
        self:SetInteractive(true)
    end,

    OnRelease = function(self)
        self:SetImage(nil)
        self.frame:EnableMouse(true)
        self:SetInteractive(true)
    end,

    SetImage = function(self, texture)
        self.image:SetTexture(texture)

        if self.image:GetTexture() then
            self.image:SetTexCoord(0, 1, 0, 1)
        end
    end,

    SetImageSize = function(self, width, height)
        self.image:SetWidth(width)
        self.image:SetHeight(height)
    end,

    SetInteractive = function(self, interactive)
        self.interactive = interactive and true or false
        self.frame:EnableMouse(self.interactive)

        if self.highlight then
            if self.interactive then
                self.highlight:SetTexture(136580)
            else
                self.highlight:SetTexture(nil)
            end
        end
    end,
}

local function CreateCenteredIconWidget()
    local frame = CreateFrame("Button", nil, UIParent)
    frame:Hide()
    frame:EnableMouse(true)
    frame:SetScript("OnClick", CenteredIcon_OnClick)

    local image = frame:CreateTexture(nil, "BACKGROUND")
    image:SetPoint("CENTER")
    image:SetWidth(UI.IconSize)
    image:SetHeight(UI.IconSize)

    local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(image)
    highlight:SetTexture(136580)
    highlight:SetTexCoord(0, 1, 0.23, 0.77)
    highlight:SetBlendMode("ADD")

    local widget = {
        frame = frame,
        image = image,
        highlight = highlight,
        type = UI.CenteredIconWidgetType,
    }

    for methodName, method in pairs(centeredIconMethods) do
        widget[methodName] = method
    end

    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(UI.CenteredIconWidgetType, CreateCenteredIconWidget, CenteredIconWidgetVersion)

function UI:CreateCenteredRowIcon()
    local icon = AceGUI:Create(self.CenteredIconWidgetType)
    icon:SetWidth(self.PlayerContainerElementSize)
    icon:SetHeight(self.PlayerContainerElementSize)
    icon:SetImageSize(self.RowActionIconSize, self.RowActionIconSize)

    return icon
end
