local AceGUI = LibStub("AceGUI-3.0")
local GearPolice = GearPolice

local UI = GearPolice.UI

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
        self:SetWidth(UI.PlayerContainerElementSize)
        self:SetHeight(UI.PlayerContainerElementSize)
        self:SetImage(nil)
        self:SetImageSize(UI.IconSize, UI.IconSize)
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
    icon:SetProblematic(false)

    return icon
end
