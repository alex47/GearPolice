local GearPolice = GearPolice

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

local function OpenHelpWindow()
    GearPolice.UI:ShowHelpWindow()
end

local function OpenSettingsWindow()
    GearPolice.UI:ShowSettingsWindow()
end

local function CloseMenu()
    CloseDropDownMenus()
end

local function AddAction(text, func)
    local info = CreateMenuInfo()
    info.text = text
    info.func = func
    info.notCheckable = true
    UIDropDownMenu_AddButton(info)
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
        return
    end

    AddTitle("GearPolice")
    AddAction("Open Main Window", OpenMainWindow)
    AddAction("Settings", OpenSettingsWindow)
    AddAction("Help", OpenHelpWindow)
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
