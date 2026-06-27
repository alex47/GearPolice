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

local function SetDisabled(widget, disabled)
    if widget and widget.SetDisabled then
        widget:SetDisabled(disabled == true)
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

local function AddCheckbox(container, label, value, onValueChanged)
    local checkbox = AceGUI:Create("CheckBox")
    checkbox:SetLabel(label)
    checkbox:SetValue(value == true)
    checkbox:SetFullWidth(true)
    if onValueChanged then
        checkbox:SetCallback("OnValueChanged", function(_widget, _event, newValue)
            onValueChanged(newValue == true)
        end)
    end
    container:AddChild(checkbox)
end

local function AddDropdown(container, label, values, order, value, onValueChanged)
    local dropdown = AceGUI:Create("Dropdown")
    dropdown:SetLabel(label)
    dropdown:SetList(values, order)
    dropdown:SetValue(value)
    dropdown:SetWidth(220)
    if onValueChanged then
        dropdown:SetCallback("OnValueChanged", function(_widget, _event, newValue)
            onValueChanged(newValue)
        end)
    end
    container:AddChild(dropdown)
end

local function AddCheckboxWithEditBox(
    container,
    checkboxLabel,
    checkboxValue,
    editLabel,
    editText,
    onCheckboxChanged,
    onEditEntered
)
    local row = AceGUI:Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")
    container:AddChild(row)

    local checkbox = AceGUI:Create("CheckBox")
    checkbox:SetLabel(checkboxLabel)
    checkbox:SetValue(checkboxValue == true)
    checkbox:SetWidth(170)
    row:AddChild(checkbox)

    local label = AceGUI:Create("Label")
    label:SetText(editLabel)
    label:SetColor(0.5, 0.5, 0.5)
    label:SetWidth(70)
    row:AddChild(label)

    local editBox = AceGUI:Create("EditBox")
    editBox:SetText(editText)
    editBox:SetWidth(120)
    SetDisabled(editBox, checkboxValue ~= true)
    row:AddChild(editBox)

    if onCheckboxChanged then
        checkbox:SetCallback("OnValueChanged", function(_widget, _event, newValue)
            local enabled = newValue == true
            onCheckboxChanged(enabled)
            SetDisabled(editBox, not enabled)
        end)
    end

    if onEditEntered then
        editBox:SetCallback("OnTextChanged", function(_widget, _event, newValue)
            onEditEntered(newValue)
        end)
        editBox:SetCallback("OnEnterPressed", function(widget, _event, newValue)
            onEditEntered(newValue)
            widget:SetText(tostring(GearPolice.Settings:GetItemLevelThreshold()))
        end)
    end
end

local function IsMinimapButtonShown()
    return GearPolice.Settings:IsMinimapIconShown()
end

local function AddGeneralSection(container)
    AddHeading(container, "General")
    AddCheckbox(container, "Show Minimap Button", IsMinimapButtonShown(), function(value)
        GearPolice.Settings:SetMinimapIconShown(value)
    end)
end

local function AddReportingSection(container)
    local reportMode = GearPolice.Settings:GetReportMode()
    if not ReportModes[reportMode] then
        reportMode = "whisper"
    end

    AddHeading(container, "Reporting")
    AddDropdown(container, "Manual Report Mode", ReportModes, ReportModeOrder, reportMode, function(value)
        GearPolice.Settings:SetReportMode(value)
    end)
    AddSpacer(container)
    AddCheckbox(
        container,
        "Auto-Whisper After Scan Completes",
        GearPolice.Settings:IsReportOfferEnabled(),
        function(value)
            GearPolice.Settings:SetReportOfferEnabled(value)
        end
    )
    AddCheckbox(container, "Show Auto-Whispers", GearPolice.Settings:IsAutoWhispersShown(), function(value)
        GearPolice.Settings:SetAutoWhispersShown(value)
    end)
end

local function AddChecksSection(container)
    AddHeading(container, "Checks")
    AddCheckbox(container, "Missing Gems", GearPolice.Settings:IsRuleEnabled("missing_gems"), function(value)
        GearPolice.Settings:SetRuleEnabled("missing_gems", value)
    end)
    AddCheckbox(container, "Missing Enchants", GearPolice.Settings:IsRuleEnabled("missing_enchant"), function(value)
        GearPolice.Settings:SetRuleEnabled("missing_enchant", value)
    end)
    AddCheckbox(container, "Missing Upgrades", GearPolice.Settings:IsRuleEnabled("missing_upgrade"), function(value)
        GearPolice.Settings:SetRuleEnabled("missing_upgrade", value)
    end)
    AddCheckbox(
        container,
        "Missing Extra Waist Gem Socket",
        GearPolice.Settings:IsRuleEnabled("missing_waist_extra_gem"),
        function(value)
            GearPolice.Settings:SetRuleEnabled("missing_waist_extra_gem", value)
        end
    )
    AddCheckbox(
        container,
        "Missing Enchant On One Ring",
        GearPolice.Settings:IsRuleEnabled("missing_enchanter_ring_enchant"),
        function(value)
            GearPolice.Settings:SetRuleEnabled("missing_enchanter_ring_enchant", value)
        end
    )
    AddCheckboxWithEditBox(
        container,
        "Low Item Level",
        GearPolice.Settings:IsRuleEnabled("low_item_level"),
        "Threshold",
        tostring(GearPolice.Settings:GetItemLevelThreshold()),
        function(value)
            GearPolice.Settings:SetRuleEnabled("low_item_level", value)
        end,
        function(value)
            return GearPolice.Settings:SetItemLevelThreshold(value)
        end
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
