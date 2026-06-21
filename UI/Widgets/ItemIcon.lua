local AceGUI = LibStub("AceGUI-3.0")
local GearPolice = GearPolice

local UI = GearPolice.UI

local ItemIconWidgetVersion = 2

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
        self:SetWidth(UI.PlayerContainerElementSize)
        self:SetHeight(UI.PlayerContainerElementSize)
        self:SetImage(nil)
        self:SetImageSize(UI.IconSize, UI.IconSize)
        self:SetVisualState("ok")
        self.frame:Enable()
    end,

    OnRelease = function(self)
        self:SetVisualState("ok")
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

    SetVisualState = function(self, state)
        self.visualState = state or "ok"
        local stateConfig = UI.ItemIconVisualStates[self.visualState] or UI.ItemIconVisualStates.ok
        ApplyFrameBackdrop(self.frame, stateConfig)
        ApplyTextureColor(self.image, stateConfig and stateConfig.imageColor)
    end,

    SetProblematic = function(self, isProblematic)
        self:SetVisualState(isProblematic and "problem" or "ok")
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
    highlight:SetTexture(136580)
    highlight:SetTexCoord(0, 1, 0.23, 0.77)
    highlight:SetBlendMode("ADD")

    local widget = {
        image = image,
        frame = frame,
        type = UI.ItemIconWidgetType,
    }

    for methodName, method in pairs(itemIconMethods) do
        widget[methodName] = method
    end

    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(UI.ItemIconWidgetType, CreateItemIconWidget, ItemIconWidgetVersion)

function UI:CreateEquipmentSlotIcon()
    local icon = AceGUI:Create(self.ItemIconWidgetType)
    icon:SetImageSize(self.IconSize, self.IconSize)
    icon:SetWidth(self.PlayerContainerElementSize)
    icon:SetHeight(self.PlayerContainerElementSize)
    icon:SetVisualState("ok")

    return icon
end
