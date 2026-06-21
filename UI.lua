local GearPolice = GearPolice

GearPolice.UI = GearPolice.UI or {}

local UI = GearPolice.UI

UI.IconSize = 20
UI.PlayerContainerElementSize = 24
UI.PlayerNameWidth = 110
UI.PlayerStatusTextWidth = 72
UI.PlayerIssueSummaryWidth = 84
UI.EquipmentIconFrameSize = 24
UI.EquipmentIconSpacing = 2
UI.ToolbarActionsWidth = 300
UI.MainWindowWidth = 900
UI.MainWindowHeight = 520
UI.MinimumWindowWidth = 820
UI.MinimumWindowHeight = 320
UI.ItemStripWidgetType = "GearPoliceItemStrip"
UI.QuestionMarkIcon = "Interface\\Icons\\INV_Misc_QuestionMark"
UI.FilterMode = "all"

UI.ItemIconVisualStates = {
    ok = {
        imageColor = { 1, 1, 1, 1 },
    },
    problem = {
        borderColor = { 1, 0.1, 0.1, 1 },
        imageColor = { 1, 1, 1, 1 },
    },
    pending = {
        borderColor = { 1, 0.82, 0, 1 },
        imageColor = { 1, 1, 1, 0.75 },
    },
    empty = {
        borderColor = { 0.45, 0.45, 0.45, 0.9 },
        backgroundColor = { 0.08, 0.08, 0.08, 0.25 },
        imageColor = { 1, 1, 1, 0.35 },
    },
}

UI.StatusTextures = {
    scanning = "Interface\\COMMON\\Indicator-Yellow",
    success = "Interface\\RaidFrame\\ReadyCheck-Ready",
    failed = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    temporary_failed = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

UI.CheckStatusTextures = {
    InProgress = "Interface\\COMMON\\Indicator-Yellow",
    Successful = "Interface\\RaidFrame\\ReadyCheck-Ready",
    Partial = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    Failed = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    TemporaryFailed = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

function UI:GetStatusTexture(status)
    return self.StatusTextures[status]
end

function UI:GetCheckStatusTexture(checkStatus)
    return self.CheckStatusTextures[checkStatus]
end

function UI:GetEquipmentIconStripWidth(slotCount)
    slotCount = slotCount or 0
    if slotCount <= 0 then
        return 0
    end

    return (slotCount * self.EquipmentIconFrameSize) + ((slotCount - 1) * self.EquipmentIconSpacing)
end
