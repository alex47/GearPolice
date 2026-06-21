local GearPolice = GearPolice

GearPolice.UI = GearPolice.UI or {}

local UI = GearPolice.UI

UI.IconSize = 16
UI.PlayerContainerElementSize = 24
UI.ItemIconWidgetType = "GearPoliceItemIcon"
UI.QuestionMarkIcon = "Interface\\Icons\\INV_Misc_QuestionMark"

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
