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

local function CreateToolbarButton(text, onClick)
    local button = AceGUI:Create("Button")
    button:SetText(text)
    button:SetWidth(100)
    button:SetHeight(24)
    button:SetCallback("OnClick", onClick)
    return button
end

function UI:ShowUI()
    if self.uiFrame then
        self:HideUI()
    end

    self.uiFrame = AceGUI:Create("Frame")
    self.uiFrame:SetTitle("GearPolice")
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
    toolbar:SetLayout("Table")
    toolbar:SetUserData("table", {
        columns = {
            { weight = 1 },
            { width = 100 },
        },
        spaceH = 0,
        spaceV = 0,
        alignV = "CENTER",
    })
    self.uiFrame:AddChild(toolbar)

    local leftControls = AceGUI:Create("SimpleGroup")
    leftControls:SetFullWidth(true)
    leftControls:SetLayout("Flow")
    toolbar:AddChild(leftControls)

    local clearButton = CreateToolbarButton("Clear", function()
        GearPolice:ClearAllTrackedPlayers()
    end)
    leftControls:AddChild(clearButton)

    local refreshButton = CreateToolbarButton("Refresh", function()
        GearPolice:ClearAllTrackedPlayers()
        GearPolice:StartGearPolicingOfGroup()
    end)
    leftControls:AddChild(refreshButton)

    local targetButton = CreateToolbarButton("Target", function()
        GearPolice:StartGearPolicingOfTarget()
    end)
    leftControls:AddChild(targetButton)

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
    leftControls:AddChild(filterDropdown)

    local settingsButton = CreateToolbarButton("Settings", function()
        GearPolice.UI:ShowSettingsWindow()
    end)
    toolbar:AddChild(settingsButton)

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
