local AceGUI = LibStub("AceGUI-3.0")
local GearPolice = GearPolice

local UI = GearPolice.UI

local ReportModes = {
    whisper = "Whisper",
    public = "Public",
    debug = "Debug",
}

local ReportModeOrder = {
    "whisper",
    "public",
    "debug",
}

local function SetDisabled(widget)
    if widget and widget.SetDisabled then
        widget:SetDisabled(true)
    end
end

local function AddText(container, text)
    local label = AceGUI:Create("Label")
    label:SetFullWidth(true)
    label:SetText(text)
    container:AddChild(label)
end

local function AddSpacer(container)
    AddText(container, " ")
end

local function AddHeading(container, text)
    AddText(container, "|cffffcc00" .. text .. "|r")
end

local function AddCheckbox(container, label, value)
    local checkbox = AceGUI:Create("CheckBox")
    checkbox:SetLabel(label)
    checkbox:SetValue(value == true)
    checkbox:SetFullWidth(true)
    SetDisabled(checkbox)
    container:AddChild(checkbox)
end

local function AddDropdown(container, label, values, order, value)
    local dropdown = AceGUI:Create("Dropdown")
    dropdown:SetLabel(label)
    dropdown:SetList(values, order)
    dropdown:SetValue(value)
    dropdown:SetWidth(220)
    SetDisabled(dropdown)
    container:AddChild(dropdown)
end

local function AddCheckboxWithEditBox(container, checkboxLabel, checkboxValue, editLabel, editText)
    local row = AceGUI:Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")
    container:AddChild(row)

    local checkbox = AceGUI:Create("CheckBox")
    checkbox:SetLabel(checkboxLabel)
    checkbox:SetValue(checkboxValue == true)
    checkbox:SetWidth(170)
    SetDisabled(checkbox)
    row:AddChild(checkbox)

    local label = AceGUI:Create("Label")
    label:SetText(editLabel)
    label:SetColor(0.5, 0.5, 0.5)
    label:SetWidth(70)
    row:AddChild(label)

    local editBox = AceGUI:Create("EditBox")
    editBox:SetText(editText)
    editBox:SetWidth(70)
    SetDisabled(editBox)
    row:AddChild(editBox)
end

local function GetGlobalSetting(settingName)
    if not GearPolice.db or not GearPolice.db.global then
        return nil
    end

    return GearPolice.db.global[settingName]
end

local function IsMinimapButtonShown()
    local minimapSettings = GetGlobalSetting("MinimapIcon")
    if type(minimapSettings) ~= "table" then
        return true
    end

    return minimapSettings.hide ~= true
end

local function AddGeneralSection(container)
    AddHeading(container, "General")
    AddCheckbox(container, "Show Minimap Button", IsMinimapButtonShown())
end

local function AddReportingSection(container)
    local reportMode = GetGlobalSetting("ReportMode")
    if not ReportModes[reportMode] then
        reportMode = "whisper"
    end

    AddHeading(container, "Reporting")
    AddDropdown(container, "Report Mode", ReportModes, ReportModeOrder, reportMode)
    AddSpacer(container)
    AddCheckbox(container, "Auto-Whisper After Scan Completes", GetGlobalSetting("ReportOfferEnabled") == true)
    AddCheckbox(container, "Show Auto-Whispers", GetGlobalSetting("HideReportOfferWhispers") ~= true)
end

local function AddChecksSection(container)
    AddHeading(container, "Checks")
    AddCheckbox(container, "Missing Gems", true)
    AddCheckbox(container, "Missing Enchants", true)
    AddCheckbox(container, "Missing Upgrades", true)
    AddCheckbox(container, "Missing Extra Waist Gem Socket", true)
    AddCheckbox(container, "Missing Enchant On One Ring", true)
    AddCheckboxWithEditBox(
        container,
        "Low Item Level",
        true,
        "Threshold",
        tostring(GearPolice.ItemLevelThreshold or 450)
    )
end

function UI:ShowSettingsWindow()
    if self.settingsFrame then
        AceGUI:Release(self.settingsFrame)
        self.settingsFrame = nil
    end

    self.settingsFrame = AceGUI:Create("Frame")
    self.settingsFrame:SetTitle("GearPolice Settings")
    self.settingsFrame:SetWidth(520)
    self.settingsFrame:SetHeight(560)
    self.settingsFrame:SetLayout("Fill")
    self.settingsFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        self.settingsFrame = nil
    end)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    self.settingsFrame:AddChild(scroll)

    AddGeneralSection(scroll)
    AddSpacer(scroll)
    AddReportingSection(scroll)
    AddSpacer(scroll)
    AddChecksSection(scroll)
end
