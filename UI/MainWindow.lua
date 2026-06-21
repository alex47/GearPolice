local AceGUI = LibStub("AceGUI-3.0")
local GearPolice = GearPolice

local UI = GearPolice.UI

function UI:ShowUI()
    if self.uiFrame then
        AceGUI:Release(self.uiFrame)
        self.uiFrame = nil
        self.playerUIElements = nil
        self.playerOrder = nil
    end

    self.uiFrame = AceGUI:Create("Frame")
    self.uiFrame:SetTitle("Gear Police")
    self.uiFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        self.uiFrame = nil
        self.playerUIElements = nil
        self.playerOrder = nil
    end)
    self.uiFrame:SetLayout("Flow")
    self.uiFrame:SetWidth(800)
    self.uiFrame:SetHeight(480)

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

    self.uiFrame.scrollWrapper = AceGUI:Create("SimpleGroup")
    self.uiFrame.scrollWrapper:SetFullWidth(true)
    self.uiFrame.scrollWrapper:SetFullHeight(true)
    self.uiFrame.scrollWrapper:SetLayout("Fill")
    self.uiFrame:AddChild(self.uiFrame.scrollWrapper)

    self.uiFrame.scrollContainer = AceGUI:Create("ScrollFrame")
    self.uiFrame.scrollContainer:SetLayout("List")
    self.uiFrame.scrollWrapper:AddChild(self.uiFrame.scrollContainer)

    self:UpdateUI()
end
