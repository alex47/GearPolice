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
            .. "removed from the list. Players who are currently close enough to inspect are scanned first. "
            .. "Out-of-range players remain waiting and are checked again periodically.\n\n"
            .. "Use Rescan Group to clear the current list and scan your group again.\n\n"
            .. "Use Scan Target to scan your current player target. Scan Target only works on player targets. "
            .. "This can be someone outside your group, but keep them targeted while the scan runs. Changing "
            .. "targets stops unfinished target work. Outside-group targets are removed from the list, while "
            .. "group members return to normal group scanning.\n\n"
            .. "Use Clear List to remove everyone from the list and stop active scans.\n\n"
            .. "Press Escape while the main GearPolice window is open to close it.\n\n"
            .. "Use Settings to open the GearPolice page in the game's AddOns settings list. "
            .. "There you can change report behavior, minimap visibility, and enabled checks. "
            .. "Opening Settings closes the main GearPolice window.\n\n"
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
        body = "Players are listed alphabetically. The Filter menu can show everyone, only players with "
            .. "problems, only players still scanning, or only failed and partial scans. Your selected "
            .. "filter is remembered automatically.\n\n"
            .. "Scanning means GearPolice is still checking the player. Done means the scan finished. "
            .. "Partial means some item data is still missing and GearPolice will try again later. "
            .. "Retry means the player could not be inspected yet, usually because inspect data was "
            .. "not ready. Failed or Cancelled means the scan did not finish.",
    },
    {
        title = "Options",
        body = "Open Settings to choose manual report mode, automatic announcements, auto-whispers, minimap button "
            .. "visibility, and which gear checks GearPolice should report. The settings page is generated in "
            .. "the game's AddOns settings list.\n\n"
            .. "Auto-Announce Summary Per Player posts a short party or raid "
            .. "message when a successful scan finds issues. It applies to grouped players, including you, "
            .. "and grouped target scans. Clean, incomplete, failed, and outside-group target scans are not "
            .. "announced. Auto-Announce In Party and Auto-Announce In Raid choose which group types receive "
            .. "these summaries. If multiple GearPolice users enable it, GearPolice chooses one announcer to "
            .. "prevent duplicate messages. Automatic summaries are not sent inside battlegrounds or "
            .. "arenas.\n\n"
            .. "Auto-Whisper Report Offer automatically whispers party or raid members when issues are found. "
            .. "Clean scans do not send an offer. They can whisper you back to request the full report. "
            .. "If more than one GearPolice user in the group has auto-whispers turned on, GearPolice chooses "
            .. "one sender automatically so players do not get duplicate offer whispers. Auto-Whisper In Party "
            .. "and Auto-Whisper In Raid choose which group types can receive automatic offers. Automatic "
            .. "offers are not sent while you are inside a battleground or arena.\n\n"
            .. "Show Auto-Whispers controls whether incoming !gp requests and GearPolice's automatic report "
            .. "offer and reply whispers appear in your chat window. Hiding them does not stop requests from "
            .. "being processed or messages from being sent.\n\n"
            .. "The Checks section controls which problems are reported on future scans. Low Item Level "
            .. "issues include the threshold that was used for the scan. Missing Upgrade issues show the "
            .. "item's current and maximum upgrade levels.",
    },
    {
        title = "Manual Reporting And Automatic Announcements",
        body = "Whisper sends manual reports privately to the player.\n\n"
            .. "Announcement sends manual reports to party or raid chat.\n\n"
            .. "Announce Changing To Manual Announcement Mode controls whether GearPolice announces in "
            .. "party or raid chat when you switch Manual Report Mode to Announcement.\n\n"
            .. "Auto-Announce Summary Per Player controls automatic "
            .. "issue-count summaries after successful scans. Its Party and Raid options control where those "
            .. "summaries are enabled.\n\n"
            .. "Debug prints manual reports only in your own chat window.",
    },
    {
        title = "Whisper Requests",
        body = "Players can whisper you !gp to get their report. If their scan is still running, clean, "
            .. "failed, or waiting on item data, GearPolice sends them a short status message instead.",
    },
    {
        title = "Combat",
        body = "GearPolice pauses all active and queued gear inspection during combat and continues afterward. "
            .. "Automatic report offer whispers and pending automatic scan summaries wait until combat is over.",
    },
    {
        title = "Commands",
        body = "/gearpolice shows the command list.\n\n"
            .. "/gearpolice scan clears the current list and performs a fresh group scan.\n\n"
            .. "/gearpolice showui opens the main window.\n\n"
            .. "/gearpolice settings opens the settings page.\n\n"
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
    self.helpFrame:SetStatusText("GearPolice v" .. version .. " | Made by " .. author)
    self.helpFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        self.helpFrame = nil
    end)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    self.helpFrame:AddChild(scroll)

    for index, section in ipairs(HelpSections) do
        if index > 1 then
            AddSpacer(scroll)
        end
        AddHeading(scroll, section.title)
        AddText(scroll, section.body)
    end
end
