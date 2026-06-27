local AceGUI = LibStub("AceGUI-3.0")
local GearPolice = GearPolice

local UI = GearPolice.UI

local FilterOptions = {
    all = "All",
    problems = "Problems",
    scanning = "Scanning",
    failed_partial = "Failed/Partial",
}

local FilterOptionOrder = {
    "all",
    "problems",
    "scanning",
    "failed_partial",
}

local ToolbarHeight = 44
local ToolbarButtonWidth = 134
local ToolbarButtonHeight = 24
local ToolbarButtonGap = 4
local ToolbarFilterGap = 8
local ToolbarControlTopOffset = -16

local function ClearWindowState(self)
    self.uiFrame = nil
    self.playerUIElements = nil
    self.playerOrder = nil
    self.detachedToolbarWidgets = nil
    self.toolbarFilterLabel = nil
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

local function ReleaseDetachedToolbarWidgets(self)
    if self.toolbarFilterLabel then
        self.toolbarFilterLabel:Hide()
        self.toolbarFilterLabel:ClearAllPoints()
        self.toolbarFilterLabel = nil
    end

    if not self.detachedToolbarWidgets then
        return
    end

    for _, widget in ipairs(self.detachedToolbarWidgets) do
        AceGUI:Release(widget)
    end

    self.detachedToolbarWidgets = nil
end

local function CreateToolbarButton(parent, text, onClick)
    local button = AceGUI:Create("Button")
    button:SetText(text)
    button:SetWidth(ToolbarButtonWidth)
    button:SetHeight(ToolbarButtonHeight)
    button:SetCallback("OnClick", onClick)
    button.frame:SetParent(parent)
    button.frame:ClearAllPoints()
    button.frame:Show()
    return button
end

local function AddDetachedToolbarWidget(self, widget)
    self.detachedToolbarWidgets[#self.detachedToolbarWidgets + 1] = widget
    return widget
end

local function CreateFilterDropdown(self, parent)
    local dropdown = AceGUI:Create("Dropdown")
    dropdown:SetLabel("")
    dropdown:SetWidth(150)
    dropdown:SetList(FilterOptions, FilterOptionOrder)
    dropdown:SetValue(self.FilterMode or "all")
    dropdown:SetCallback("OnValueChanged", function(_widget, _event, value)
        self.FilterMode = value or "all"
        self:UpdateUI()
    end)
    dropdown.frame:SetParent(parent)
    dropdown.frame:ClearAllPoints()
    dropdown.frame:Show()
    return dropdown
end

local function CreateMainToolbar(self)
    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetFullWidth(true)
    toolbar:SetHeight(ToolbarHeight)
    toolbar.noAutoHeight = true
    toolbar:SetLayout("Fill")
    self.uiFrame:AddChild(toolbar)

    local content = toolbar.content
    self.detachedToolbarWidgets = {}

    local clearButton = AddDetachedToolbarWidget(self, CreateToolbarButton(content, "Clear List", function()
        GearPolice:ClearAllTrackedPlayers()
    end))
    clearButton.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, ToolbarControlTopOffset)

    local refreshButton = AddDetachedToolbarWidget(self, CreateToolbarButton(content, "Rescan Group", function()
        GearPolice:ClearAllTrackedPlayers()
        GearPolice:StartGearPolicingOfGroup()
    end))
    refreshButton.frame:SetPoint("TOPLEFT", clearButton.frame, "TOPRIGHT", ToolbarButtonGap, 0)

    local targetButton = AddDetachedToolbarWidget(self, CreateToolbarButton(content, "Scan Target", function()
        GearPolice:StartGearPolicingOfTarget()
    end))
    targetButton.frame:SetPoint("TOPLEFT", refreshButton.frame, "TOPRIGHT", ToolbarButtonGap, 0)

    local filterDropdown = AddDetachedToolbarWidget(self, CreateFilterDropdown(self, content))
    filterDropdown.frame:SetPoint("TOPLEFT", targetButton.frame, "TOPRIGHT", ToolbarFilterGap, 0)

    local filterLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLabel:SetText("Filter")
    filterLabel:SetPoint("BOTTOMLEFT", filterDropdown.frame, "TOPLEFT", 0, -1)
    self.toolbarFilterLabel = filterLabel

    local settingsButton = AddDetachedToolbarWidget(self, CreateToolbarButton(content, "Settings", function()
        GearPolice.UI:ShowSettingsWindow()
    end))
    settingsButton.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, ToolbarControlTopOffset)
end

function UI:ShowUI()
    if self.uiFrame then
        self:HideUI()
    end

    self.uiFrame = AceGUI:Create("Frame")
    self.uiFrame:SetTitle("GearPolice")
    self.uiFrame:SetCallback("OnClose", function(widget)
        ReleaseDetachedToolbarWidgets(self)
        AceGUI:Release(widget)
        ClearWindowState(self)
    end)
    self.uiFrame:SetLayout("Flow")
    self.uiFrame:SetWidth(UI.MainWindowWidth)
    self.uiFrame:SetHeight(UI.MainWindowHeight)
    SetResizeBounds(self.uiFrame)

    self.playerUIElements = {}
    self.playerOrder = {}

    CreateMainToolbar(self)

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

    ReleaseDetachedToolbarWidgets(self)
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
