local GearPolice = GearPolice

local REPORT_MODE_MENU_VALUE = "REPORT_MODE"

local ReportModes = {
    { value = "whisper", label = "Whisper" },
    { value = "public", label = "Public" },
    { value = "debug", label = "Debug" },
}

local function CreateMenuInfo()
    return UIDropDownMenu_CreateInfo()
end

local function AddTitle(text)
    local info = CreateMenuInfo()
    info.text = text
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info)
end

local function AddSeparator()
    local info = CreateMenuInfo()
    info.text = ""
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info)
end

local function OpenMainWindow()
    if not GearPolice.UI.uiFrame then
        GearPolice.UI:ShowUI()
    end
end

local function CloseMenu()
    CloseDropDownMenus()
end

local function SetReportMode(_button, reportMode)
    GearPolice.db.global.ReportMode = reportMode
end

local function ToggleReportOffers()
    GearPolice.db.global.ReportOfferEnabled = GearPolice.db.global.ReportOfferEnabled ~= true
end

local function ToggleHideReportWhispers()
    GearPolice.db.global.HideReportOfferWhispers = GearPolice.db.global.HideReportOfferWhispers ~= true
end

local function AddAction(text, func)
    local info = CreateMenuInfo()
    info.text = text
    info.func = func
    info.notCheckable = true
    UIDropDownMenu_AddButton(info)
end

local function AddToggle(text, isChecked, func)
    local info = CreateMenuInfo()
    info.text = text
    info.func = func
    info.checked = isChecked
    info.isNotRadio = true
    info.keepShownOnClick = true
    UIDropDownMenu_AddButton(info)
end

local function AddReportModeSubmenu()
    local info = CreateMenuInfo()
    info.text = "Report Mode"
    info.hasArrow = true
    info.value = REPORT_MODE_MENU_VALUE
    info.notCheckable = true
    UIDropDownMenu_AddButton(info)
end

local function AddReportModeOptions(level)
    for _, reportMode in ipairs(ReportModes) do
        local info = CreateMenuInfo()
        info.text = reportMode.label
        info.arg1 = reportMode.value
        info.func = SetReportMode
        info.checked = GearPolice.db.global.ReportMode == reportMode.value
        info.level = level
        UIDropDownMenu_AddButton(info, level)
    end
end

function GearPolice:InitializeMinimapDropDown(frame)
    UIDropDownMenu_SetInitializeFunction(frame, function(dropdownFrame, level)
        GearPolice:InitializeMinimapDropDownItems(dropdownFrame, level)
    end)
    UIDropDownMenu_SetDisplayMode(frame, "MENU")
end

function GearPolice:InitializeMinimapDropDownItems(_frame, level)
    level = level or 1

    if level > 1 then
        if UIDROPDOWNMENU_MENU_VALUE == REPORT_MODE_MENU_VALUE then
            AddReportModeOptions(level)
        end
        return
    end

    AddTitle("GearPolice")
    AddAction("Open Main Window", OpenMainWindow)
    AddSeparator()
    AddReportModeSubmenu()
    AddToggle("Report Offers", GearPolice.db.global.ReportOfferEnabled == true, ToggleReportOffers)
    AddToggle("Hide GP Whispers", GearPolice.db.global.HideReportOfferWhispers == true, ToggleHideReportWhispers)
    AddSeparator()
    AddAction("Close", CloseMenu)
end

function GearPolice:OpenMinimapDropDown(clickedFrame)
    local dropdownFrame = _G.GearPoliceMinimapDropDown

    if not dropdownFrame then
        return
    end

    if AddonCompartmentFrame
        and clickedFrame
        and clickedFrame.GetParent
        and clickedFrame:GetParent() == DropDownList1 then
        ToggleDropDownMenu(1, nil, dropdownFrame, "cursor", 0, 0)
    else
        ToggleDropDownMenu(1, nil, dropdownFrame, clickedFrame:GetName(), 0, -5)
    end
end
