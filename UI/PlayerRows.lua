local AceGUI = LibStub("AceGUI-3.0")
local GearPolice = GearPolice

local UI = GearPolice.UI

UI.PlayerRows = UI.PlayerRows or {}

local PlayerRows = UI.PlayerRows

function UI:UpdatePlayerStatusIcon(playerGuid, status)
    if not self.playerUIElements then return end

    local playerUI = self.playerUIElements[playerGuid]
    if not playerUI then return end

    playerUI.statusIcon:SetImage(self:GetStatusTexture(status))
end

local function NeedsRebuild(ui, rows)
    for playerGuid in pairs(ui.playerUIElements) do
        if not GearPolice.db.global.PlayerGearInfo[playerGuid] then
            return true
        end
    end

    local playerOrder = ui.playerOrder or {}
    if #playerOrder ~= #rows then
        return true
    end

    for index, row in ipairs(rows) do
        if playerOrder[index] ~= row.playerGuid then
            return true
        end
    end

    return false
end

local function CreatePlayerRow(scrollContainer)
    local playerContainer = AceGUI:Create("SimpleGroup")
    playerContainer:SetFullWidth(true)
    playerContainer:SetLayout("Flow")
    playerContainer:SetHeight(UI.PlayerContainerElementSize)

    local reportButton = AceGUI:Create("Icon")
    reportButton:SetImage("Interface\\COMMON\\VOICECHAT-SPEAKER")
    reportButton:SetImageSize(UI.IconSize, UI.IconSize)
    reportButton:SetWidth(UI.PlayerContainerElementSize)
    reportButton:SetHeight(UI.PlayerContainerElementSize)
    playerContainer:AddChild(reportButton)

    local statusIcon = AceGUI:Create("Icon")
    statusIcon:SetImageSize(UI.IconSize, UI.IconSize)
    statusIcon:SetWidth(UI.PlayerContainerElementSize)
    statusIcon:SetHeight(UI.PlayerContainerElementSize)
    statusIcon:SetImage("Interface\\COMMON\\Indicator-Yellow")
    playerContainer:AddChild(statusIcon)

    local statusLabel = AceGUI:Create("Label")
    statusLabel:SetWidth(UI.PlayerStatusTextWidth)
    statusLabel:SetHeight(UI.PlayerContainerElementSize)
    statusLabel:SetJustifyV("MIDDLE")
    playerContainer:AddChild(statusLabel)

    local playerNameLabel = AceGUI:Create("Label")
    playerNameLabel:SetWidth(UI.PlayerNameWidth)
    playerNameLabel:SetHeight(UI.PlayerContainerElementSize)
    playerNameLabel:SetJustifyV("MIDDLE")
    playerContainer:AddChild(playerNameLabel)

    local issueSummaryLabel = AceGUI:Create("Label")
    issueSummaryLabel:SetWidth(UI.PlayerIssueSummaryWidth)
    issueSummaryLabel:SetHeight(UI.PlayerContainerElementSize)
    issueSummaryLabel:SetJustifyV("MIDDLE")
    playerContainer:AddChild(issueSummaryLabel)

    local itemStrip = UI:CreateEquipmentIconStrip()
    playerContainer:AddChild(itemStrip)

    scrollContainer:AddChild(playerContainer)

    return {
        playerContainer = playerContainer,
        reportButton = reportButton,
        statusIcon = statusIcon,
        statusLabel = statusLabel,
        playerNameLabel = playerNameLabel,
        issueSummaryLabel = issueSummaryLabel,
        itemStrip = itemStrip,
    }
end

local function UpdatePlayerRow(playerUI, row)
    playerUI.reportButton:SetCallback("OnClick", function()
        GearPolice.Reporting:ReportProblematicItems(row.playerInfo)
    end)

    GearPolice.Debug:Message("playerInfo.CheckStatus: " .. (row.checkStatus or "nil"))
    playerUI.statusIcon:SetImage(row.statusTexture)
    playerUI.statusLabel:SetText(row.statusText or "")
    playerUI.issueSummaryLabel:SetText(row.issueSummary or "")

    if row.hasProblems then
        playerUI.playerNameLabel:SetText("|cffFF0000" .. row.playerName .. "|r")
    else
        playerUI.playerNameLabel:SetText("|cffFFFFFF" .. row.playerName .. "|r")
    end

    playerUI.itemStrip:SetSlots(row.slots)
end

function PlayerRows.Render(ui, scrollContainer, rows)
    ui.playerUIElements = ui.playerUIElements or {}

    if NeedsRebuild(ui, rows) then
        scrollContainer:ReleaseChildren()
        ui.playerUIElements = {}
    end

    ui.playerOrder = {}
    for _, row in ipairs(rows) do
        table.insert(ui.playerOrder, row.playerGuid)

        local playerUI = ui.playerUIElements[row.playerGuid]
        if not playerUI then
            playerUI = CreatePlayerRow(scrollContainer)
            ui.playerUIElements[row.playerGuid] = playerUI
        end

        UpdatePlayerRow(playerUI, row)
    end
end

function UI:UpdateUI()
    if not self.uiFrame or not self.uiFrame:IsVisible() then
        return
    end

    local rows, summary = self.ViewModel.BuildRows(self.FilterMode or "all")
    if summary then
        self.uiFrame:SetStatusText(summary.text or "")
    end

    self.PlayerRows.Render(self, self.uiFrame.scrollContainer, rows)
    self.uiFrame:DoLayout()
end
