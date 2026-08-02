local GearPolice = GearPolice

local Inspection = GearPolice.Inspection
local Constants = GearPolice.Constants

local function GetUpgradeScanTooltip()
    if not Inspection.upgradeScanTooltip then
        Inspection.upgradeScanTooltip = CreateFrame(
            "GameTooltip",
            "GearPoliceUpgradeScanTooltip",
            UIParent,
            "GameTooltipTemplate"
        )
    end

    return Inspection.upgradeScanTooltip
end

local function ParseUpgradeLevelText(text)
    if not text then
        return nil, nil
    end

    local currentUpgrade, maximumUpgrade = text:match("Upgrade Level:%s*(%d+)%s*/%s*(%d+)")
    if not currentUpgrade or not maximumUpgrade then
        return nil, nil
    end

    return tonumber(currentUpgrade), tonumber(maximumUpgrade)
end

local function ReadUpgradeLevelFromTooltip(tooltip)
    local tooltipName = tooltip:GetName()
    if not tooltipName then
        return nil, nil, false
    end

    local sawUpgradeText = false
    for i = 1, tooltip:NumLines() do
        local textLine = _G[tooltipName .. "TextLeft" .. i]
        local text = textLine and textLine:GetText()
        local currentUpgrade, maximumUpgrade = ParseUpgradeLevelText(text)

        if currentUpgrade and maximumUpgrade then
            return currentUpgrade, maximumUpgrade, true
        end

        if text and text:find("Upgrade") then
            sawUpgradeText = true
        end
    end

    return nil, nil, sawUpgradeText
end

function Inspection:IsItemInfoAvailable(itemLink)
    if not itemLink then
        return false
    end

    local itemName = GetItemInfo(itemLink)
    return itemName ~= nil
end

function Inspection:CountSocketSlots(itemLink)
    if not itemLink then
        return 0
    end

    local tempTable = {}
    local itemStats = GetItemStats(itemLink, tempTable)

    if not itemStats then
        if not self:IsItemInfoAvailable(itemLink) then
            return Constants.ItemMetadataPending
        end

        return 0
    end

    local socketSlotCount = 0
    for label, value in pairs(itemStats) do
        if label:match("EMPTY_SOCKET_") then
            socketSlotCount = socketSlotCount + (tonumber(value) or 1)
        end
    end

    return socketSlotCount
end

function Inspection:CountSocketedGemIds(itemLink, maxGemFields)
    if not itemLink then
        return 0
    end

    maxGemFields = maxGemFields or 4
    if maxGemFields > 4 then
        maxGemFields = 4
    end

    local itemString = itemLink:match("item:([^|]+)")
    if not itemString then
        return 0
    end

    local _, _, gemId1, gemId2, gemId3, gemId4 = strsplit(":", itemString)
    local gemIds = { gemId1, gemId2, gemId3, gemId4 }
    local socketedGemCount = 0

    for i = 1, maxGemFields do
        local gemId = gemIds[i]
        if gemId and gemId ~= "" and gemId ~= "0" then
            socketedGemCount = socketedGemCount + 1
        end
    end

    return socketedGemCount
end

function Inspection:IsItemMissingGems(itemLink)
    if not itemLink then
        return false
    end

    local socketSlotCount = self:CountSocketSlots(itemLink)

    if self:IsItemMetadataPending(socketSlotCount) then
        return Constants.ItemMetadataPending
    end

    if socketSlotCount == 0 then
        return false
    end

    if socketSlotCount > 4 then
        return Constants.ItemMetadataPending
    end

    local socketedGemCount = self:CountSocketedGemIds(itemLink, socketSlotCount)
    return socketedGemCount < socketSlotCount
end

function Inspection:IsItemMissingEnchant(itemLink)
    if not itemLink then
        return false
    end

    local enchantID = select(3, strsplit(":", itemLink))

    return (not enchantID) or enchantID == "" or enchantID == "0"
end

function Inspection:IsItemBelowItemLevel(itemLink)
    if not itemLink then
        return false
    end

    local itemLevel, _, _ = GetDetailedItemLevelInfo(itemLink)

    if not itemLevel then
        return Constants.ItemMetadataPending
    end

    return itemLevel < GearPolice.Settings:GetItemLevelThreshold()
end

function Inspection:IsWaistMissingExtraGemEnchant(itemLink)
    if not itemLink then return false end

    local base = self:CountSocketSlots(itemLink)
    if self:IsItemMetadataPending(base) then
        return Constants.ItemMetadataPending
    end

    if base == 0 then return false end

    local inserted = self:CountSocketedGemIds(itemLink, 4)

    if inserted < base then return false end
    if inserted == base then return true end
    return false
end

function Inspection:GetIncorrectArmorTypeResult(itemLink, context)
    if not itemLink or type(context) ~= "table" then
        return false
    end

    local unitLevel = tonumber(context.unitLevel)
    if not unitLevel or unitLevel <= 0 then
        return Constants.ItemMetadataPending
    end

    if unitLevel < GearPolice.GearStandards.MinimumArmorSpecializationLevel then
        return false
    end

    local expectedArmorType = context.expectedArmorType
    if not expectedArmorType then
        return Constants.ItemMetadataPending
    end

    local itemName, _, _, _, _, _, itemSubType, _, _, _, _, itemClassId, itemSubclassId =
        GetItemInfo(itemLink)
    if not itemName then
        return Constants.ItemMetadataPending
    end

    if itemClassId and itemClassId ~= GearPolice.GearStandards.ArmorItemClassId then
        return false
    end

    local actualArmorType = GearPolice.GearStandards.GetArmorTypeBySubclassId(itemSubclassId)
        or GearPolice.GearStandards.GetArmorTypeByName(itemSubType)
    if not actualArmorType or actualArmorType == expectedArmorType then
        return false
    end

    return {
        actualArmorType = actualArmorType,
        expectedArmorType = expectedArmorType,
    }
end

function Inspection:GetIncorrectPrimaryStatResult(itemLink, context)
    if not itemLink or type(context) ~= "table" then
        return false
    end

    local expectedPrimaryStat = context.expectedPrimaryStat
    if not expectedPrimaryStat then
        local unitLevel = tonumber(context.unitLevel)
        if unitLevel and unitLevel < GearPolice.GearStandards.MinimumSpecializationLevel then
            return false
        end

        return Constants.ItemMetadataPending
    end

    local itemStats = GetItemStats(itemLink, {})
    if not itemStats then
        if not self:IsItemInfoAvailable(itemLink) then
            return Constants.ItemMetadataPending
        end

        return false
    end

    local actualPrimaryStats = {}
    local actualPrimaryStatLabels = {}
    for _, primaryStat in ipairs(GearPolice.GearStandards.GetOrderedPrimaryStats()) do
        local definition = GearPolice.GearStandards.GetPrimaryStatDefinition(primaryStat)
        if definition and (tonumber(itemStats[definition.itemStatKey]) or 0) > 0 then
            actualPrimaryStats[primaryStat] = true
            table.insert(actualPrimaryStatLabels, definition.label)
        end
    end

    if #actualPrimaryStatLabels == 0 or actualPrimaryStats[expectedPrimaryStat] then
        return false
    end

    return {
        actualPrimaryStatLabels = actualPrimaryStatLabels,
        expectedPrimaryStatLabel = GearPolice.GearStandards.GetPrimaryStatLabel(expectedPrimaryStat),
    }
end

function Inspection:GetInventorySlotUpgradeLevel(unitId, slotID)
    if not unitId or not slotID or not UnitExists(unitId) then
        return nil, nil, Constants.ItemMetadataPending
    end

    local tooltip = GetUpgradeScanTooltip()
    tooltip:ClearLines()
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")

    local hasItem = tooltip:SetInventoryItem(unitId, slotID)
    local lineCount = tooltip:NumLines()
    local _, tooltipItemLink = tooltip:GetItem()
    local currentUpgrade, maximumUpgrade, sawUpgradeText = ReadUpgradeLevelFromTooltip(tooltip)

    tooltip:Hide()

    if not hasItem or not tooltipItemLink or lineCount == 0 then
        return nil, nil, Constants.ItemMetadataPending
    end

    if currentUpgrade and maximumUpgrade then
        return currentUpgrade, maximumUpgrade, nil
    end

    if sawUpgradeText then
        return nil, nil, Constants.ItemMetadataPending
    end

    return nil, nil, nil
end

function Inspection:GetMissingUpgradeResult(itemLink, unitId, slotID)
    if not itemLink then
        return false
    end

    local currentUpgrade, maximumUpgrade, pending = self:GetInventorySlotUpgradeLevel(unitId, slotID)
    if self:IsItemMetadataPending(pending) then
        return Constants.ItemMetadataPending
    end

    if not currentUpgrade or not maximumUpgrade then
        return false
    end

    if currentUpgrade >= maximumUpgrade then
        return false
    end

    return {
        currentUpgrade = currentUpgrade,
        maximumUpgrade = maximumUpgrade,
    }
end
