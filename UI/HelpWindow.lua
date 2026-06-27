local AceGUI = LibStub("AceGUI-3.0")
local GearPolice = GearPolice

local UI = GearPolice.UI
local AddonName = "GearPolice"

local HelpSections = {
    {
        title = "What It Does",
        body = "GearPolice checks equipped gear for missing gems, missing enchants, missing upgrades, "
            .. "low item level, and special ring enchant cases.",
    },
    {
        title = "How To Use",
        body = "GearPolice automatically watches your party or raid. When you join a group, it starts "
            .. "a fresh list and begins scanning the group, including you. When players leave, they are "
            .. "removed from the list.\n\n"
            .. "Use Rescan Group to clear the current list and scan your group again.\n\n"
            .. "Use Scan Target to scan your current player target. Scan Target only works on player targets. "
            .. "This can be someone outside your group, but keep them targeted while the scan runs.\n\n"
            .. "Use Clear List to remove everyone from the list and stop active scans.\n\n"
            .. "Use Settings to change report behavior, minimap visibility, and enabled checks. "
            .. "GearPolice also has a generated settings page in the game's AddOns settings list.\n\n"
            .. "Each player row has a small speaker button on the left. Click it to send that player's "
            .. "report using the selected Manual Report Mode.\n\n"
            .. "Hover item icons to see the item and any GearPolice issues found on it.",
    },
    {
        title = "Minimap Button",
        body = "Left-click the GearPolice minimap button to open or close the main window.\n\n"
            .. "Right-click it to open Settings, Help, or the main window.",
    },
    {
        title = "Filters And Status",
        body = "The Filter menu can show everyone, only players with problems, only players still "
            .. "scanning, or only failed and partial scans.\n\n"
            .. "Scanning means GearPolice is still checking the player. Done means the scan finished. "
            .. "Partial means some item data is still missing and GearPolice will try again later. "
            .. "Retry means the player could not be inspected yet, usually because inspect data was "
            .. "not ready. Failed or Cancelled means the scan did not finish.",
    },
    {
        title = "Options",
        body = "Open Settings to choose manual report mode, auto-whispers, minimap button visibility, and which "
            .. "gear checks GearPolice should report. You can also find GearPolice in the game's AddOns "
            .. "settings list; that page is generated from the same settings.\n\n"
            .. "Auto-Whisper After Scan Completes automatically whispers party or raid members when issues are found. "
            .. "Clean scans do not send an offer. They can whisper you back to request the full report. "
            .. "GearPolice waits 12 hours before offering the same player again. If more than one "
            .. "GearPolice user in the group has auto-whispers turned on, GearPolice chooses one sender "
            .. "automatically so players do not get duplicate offer whispers.\n\n"
            .. "Show Auto-Whispers controls whether GearPolice's automatic offer and reply whispers are shown "
            .. "in your chat window. The whispers are still sent normally when this is off.\n\n"
            .. "The Checks section controls which problems are reported on future scans.",
    },
    {
        title = "Manual Report Modes",
        body = "Whisper sends manual reports privately to the player.\n\n"
            .. "Public sends manual reports to party or raid chat.\n\n"
            .. "Debug prints manual reports only in your own chat window.",
    },
    {
        title = "Whisper Requests",
        body = "Players can whisper you !gp to get their report. If their scan is still running, clean, "
            .. "failed, or waiting on item data, GearPolice sends them a short status message instead.",
    },
    {
        title = "Combat",
        body = "GearPolice pauses group scanning during combat and continues afterward. Automatic report "
            .. "offer whispers also wait until combat is over.",
    },
    {
        title = "Commands",
        body = "/gearpolice shows the command list.\n\n"
            .. "/gearpolice scan starts a group scan.\n\n"
            .. "/gearpolice showui opens the main window.\n\n"
            .. "/gearpolice settings opens the settings window.\n\n"
            .. "/gearpolice target scans your current player target.\n\n"
            .. "/gearpolice help opens this help window.\n\n"
            .. "/gearpolice debug toggles debug messages.",
    },
}

local function GetAddonMetadata(fieldName)
    local getter = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if type(getter) ~= "function" then
        return nil
    end

    return getter(AddonName, fieldName)
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

function UI:ShowHelpWindow()
    if self.helpFrame then
        AceGUI:Release(self.helpFrame)
        self.helpFrame = nil
    end

    local version = GetAddonMetadata("Version") or "Unknown"
    local author = GetAddonMetadata("Author") or "Unknown"

    self.helpFrame = AceGUI:Create("Frame")
    self.helpFrame:SetTitle("GearPolice Help")
    self.helpFrame:SetWidth(620)
    self.helpFrame:SetHeight(540)
    self.helpFrame:SetLayout("Fill")
    self.helpFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        self.helpFrame = nil
    end)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    self.helpFrame:AddChild(scroll)

    AddText(scroll, "|cff40ff40GearPolice v" .. version .. "|r")
    AddText(scroll, "|cffBBBBBBMade by " .. author .. "|r")
    AddSpacer(scroll)

    for index, section in ipairs(HelpSections) do
        if index > 1 then
            AddSpacer(scroll)
        end
        AddHeading(scroll, section.title)
        AddText(scroll, section.body)
    end
end
