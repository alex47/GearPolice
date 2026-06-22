local AceGUI = LibStub("AceGUI-3.0")
local GearPolice = GearPolice

local UI = GearPolice.UI

local function ClearWindowState(self)
    self.uiFrame = nil
    self.playerUIElements = nil
    self.playerOrder = nil
end

local function SetResizeBounds(frameWidget)
    local frame = frameWidget and frameWidget.frame
    if not frame then
        return
    end

    if frame.SetResizeBounds then
        frame:SetResizeBounds(UI.MinimumWindowWidth, UI.MinimumWindowHeight)
    else
        frame:SetMinResize(UI.MinimumWindowWidth, UI.MinimumWindowHeight)
    end
end

function UI:ShowUI()
    if self.uiFrame then
        self:HideUI()
    end

    self.uiFrame = AceGUI:Create("Frame")
    self.uiFrame:SetTitle("Gear Police")
    self.uiFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        ClearWindowState(self)
    end)
    self.uiFrame:SetLayout("Flow")
    self.uiFrame:SetWidth(UI.MainWindowWidth)
    self.uiFrame:SetHeight(UI.MainWindowHeight)
    SetResizeBounds(self.uiFrame)

    self.playerUIElements = {}
    self.playerOrder = {}

    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetFullWidth(true)
    toolbar:SetLayout("Flow")
    self.uiFrame:AddChild(toolbar)

    local scanActions = AceGUI:Create("SimpleGroup")
    scanActions:SetWidth(UI.ToolbarActionsWidth)
    scanActions:SetLayout("Flow")
    toolbar:AddChild(scanActions)

    local clearButton = AceGUI:Create("Button")
    clearButton:SetText("Clear")
    clearButton:SetWidth(100)
    clearButton:SetHeight(24)
    clearButton:SetCallback("OnClick", function()
        GearPolice:ClearAllTrackedPlayers()
    end)
    scanActions:AddChild(clearButton)

    local refreshButton = AceGUI:Create("Button")
    refreshButton:SetText("Refresh")
    refreshButton:SetWidth(100)
    refreshButton:SetHeight(24)
    refreshButton:SetCallback("OnClick", function()
        GearPolice:ClearAllTrackedPlayers()
        GearPolice:StartGearPolicingOfGroup()
    end)
    scanActions:AddChild(refreshButton)

    local targetButton = AceGUI:Create("Button")
    targetButton:SetText("Target")
    targetButton:SetWidth(100)
    targetButton:SetHeight(24)
    targetButton:SetCallback("OnClick", function()
        GearPolice:StartGearPolicingOfTarget()
    end)
    scanActions:AddChild(targetButton)

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
    toolbar:AddChild(reportModeDropdown)

    local filterDropdown = AceGUI:Create("Dropdown")
    filterDropdown:SetLabel("Filter")
    filterDropdown:SetWidth(150)
    filterDropdown:SetList({
        all = "All",
        problems = "Problems",
        scanning = "Scanning",
        failed_partial = "Failed/Partial",
    }, {
        "all",
        "problems",
        "scanning",
        "failed_partial",
    })
    filterDropdown:SetValue(self.FilterMode or "all")
    filterDropdown:SetCallback("OnValueChanged", function(_widget, _event, value)
        self.FilterMode = value or "all"
        self:UpdateUI()
    end)
    toolbar:AddChild(filterDropdown)

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

function UI:HideUI()
    if not self.uiFrame then
        return
    end

    AceGUI:Release(self.uiFrame)
    ClearWindowState(self)
end

function UI:ToggleUI()
    if self.uiFrame then
        self:HideUI()
    else
        self:ShowUI()
    end
end
