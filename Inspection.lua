local GearPolice = GearPolice

GearPolice.Inspection = GearPolice.Inspection or {}
local Inspection = GearPolice.Inspection

local ItemLevelThreshold = 450


-- Exponential backoff helper for retry delays (with cap and light jitter)
local function InspectionRetryDelay(attempt)
    local base = 0.5 * (2 ^ (attempt - 1))
    local delay = math.min(base, 10)
    local jitter = 0.9 + math.random() * 0.2 -- 0.9x to 1.1x
    return delay * jitter
end


function Inspection:IsItemMissingGems(itemLink)
    if not itemLink then 
        return false 
    end

    local tempTable = {}

    local itemStats = GetItemStats(itemLink, tempTable)

    if not itemStats then 
        return false 
    end 

    local gemSlotCount = 0

    for label, _ in pairs(itemStats) do
        if label:match("EMPTY_SOCKET_") then
            gemSlotCount = gemSlotCount + 1
        end
    end

    if gemSlotCount == 0 then 
        return false 
    end

    local socketedGemCount = 0
    local toCheck = math.min(gemSlotCount, 3)
    for i = 1, toCheck do
        local gemName, gemLink = GetItemGem(itemLink, i)
        if gemLink or gemName then
            socketedGemCount = socketedGemCount + 1
        end
    end

    return socketedGemCount < gemSlotCount
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
        return false
    end

    return itemLevel < ItemLevelThreshold
end

function Inspection:IsWaistMissingExtraGemEnchant(itemLink)
    if not itemLink then return false end

    local stats = {}
    local itemStats = GetItemStats(itemLink, stats)
    if not itemStats then return false end

    local base = (stats["EMPTY_SOCKET_RED"] or 0)
               + (stats["EMPTY_SOCKET_YELLOW"] or 0)
               + (stats["EMPTY_SOCKET_BLUE"] or 0)

    if base == 0 then return false end

    local inserted = 0
    for i = 1, 3 do
        local name, link = GetItemGem(itemLink, i)
        if link or name then inserted = inserted + 1 end
    end

    if inserted < base then return false end
    if inserted == base then return true end
    return false
end

function Inspection:IsItemMissingUpgrade(itemLink, unitId, slotID)
    if not itemLink or not unitId or not slotID then
        return false
    end

    if not self.upgradeScanTooltip then
        self.upgradeScanTooltip = CreateFrame("GameTooltip", "GearPoliceUpgradeScanTooltip", UIParent, "GameTooltipTemplate")
    end

    local tooltip = self.upgradeScanTooltip
    tooltip:ClearLines()
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")

    if not tooltip:SetInventoryItem(unitId, slotID) then
        tooltip:Hide()
        return false
    end

    local upgradePattern = ITEM_UPGRADE_TOOLTIP_FORMAT and ITEM_UPGRADE_TOOLTIP_FORMAT:gsub("%%d", "(%%d+)") or "Upgrade Level:%s*(%%d+)/(%%d+)"
    local current, max = nil, nil

    local numLines = tooltip:NumLines()
    for i = 1, numLines do
        local leftRegion = _G[tooltip:GetName() .. "TextLeft" .. i]
        local rightRegion = _G[tooltip:GetName() .. "TextRight" .. i]
        local leftText = leftRegion and leftRegion:GetText()
        local rightText = rightRegion and rightRegion:GetText()

        if leftText then
            current, max = leftText:match(upgradePattern)
        end
        if (not current or not max) and rightText then
            current, max = rightText:match(upgradePattern)
        end
        if current and max then
            break
        end
    end

    tooltip:Hide()

    current, max = tonumber(current or 0), tonumber(max or 0)
    if not current or not max or max == 0 then
        return false
    end

    return current < max
end

function Inspection:CheckItemSlotWithRetry(playerInfo, slotName, itemCheckFunction, message, retryCount, onComplete, attempt)
    if not retryCount then
        retryCount = 1024
    end

    if not attempt then
        attempt = 1
    end

    if retryCount <= 0 then
        GearPolice.Debug:Message("Failed to inspect " .. slotName .. " for " .. playerInfo.PlayerName)
        onComplete()
        return
    end

    local unitId = GearPolice.Helper:GetUnitIdOfPlayerGuid(playerInfo.PlayerGuid)
    if not unitId then
        onComplete()
        return
    end

    local slotID = GetInventorySlotInfo(slotName)
    local itemLink = GetInventoryItemLink(unitId, slotID)

    if itemLink then
        if itemCheckFunction(itemLink, unitId, slotID) then
            if not playerInfo.ProblematicItems[itemLink] then
                playerInfo.ProblematicItems[itemLink] = {}
            end
            table.insert(playerInfo.ProblematicItems[itemLink], message)
        end
        onComplete()
    else
        -- An item may be equipped but its link isn't available yet; retry with backoff.
        local delay = InspectionRetryDelay(attempt)
        GearPolice:ScheduleManagedTimer(function()
            Inspection:CheckItemSlotWithRetry(playerInfo, slotName, itemCheckFunction, message, retryCount - 1, onComplete, attempt + 1)
        end, delay)
    end
end

function Inspection:IsTwoHandedOrRangedWeaponEquipped(playerInfo)
    local unitId = GearPolice.Helper:GetUnitIdOfPlayerGuid(playerInfo.PlayerGuid)
    if not unitId then return false end

    local slotID = GetInventorySlotInfo("MainHandSlot")
    local link = GetInventoryItemLink(unitId, slotID)
    if not link then return false end

    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    return equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_RANGED"
end

function Inspection:CheckUnit(playerInfo, onComplete)
    -- Reset problematic items and initialize the pending checks counter.
    playerInfo.ProblematicItems = {}
    playerInfo.pendingChecks = 0

    local checks = {
        gems = {
            func = function(itemLink) return self:IsItemMissingGems(itemLink) end,
            message = "Missing Gem"
        },
        enchant = {
            func = function(itemLink) return self:IsItemMissingEnchant(itemLink) end,
            message = "Missing Enchant"
        },
        waistEnchant = {
            func = function(itemLink) return self:IsWaistMissingExtraGemEnchant(itemLink) end,
            message = "Missing Extra Waist Gem Enchant"
        },
        upgrade = {
            func = function(itemLink, unitId, slotID) return self:IsItemMissingUpgrade(itemLink, unitId, slotID) end,
            message = "Missing Upgrade"
        },
        ilevel = {
            func = function(itemLink) return self:IsItemBelowItemLevel(itemLink) end,
            message = "Low Item Level"
        },
    }

    local slotConfig = {
        HeadSlot          = { "gems",            "ilevel", "upgrade" }, -- Remove head enchant temporarily as there aren't any in the game yet as of MoP Phase 1.
        HeadSlot          = { "gems",            "ilevel", "upgrade" },
        NeckSlot          = { "gems",            "ilevel", "upgrade" },
        ShoulderSlot      = { "gems", "enchant", "ilevel", "upgrade" },
        BackSlot          = { "gems", "enchant", "ilevel", "upgrade" },
        ChestSlot         = { "gems", "enchant", "ilevel", "upgrade" },
        WristSlot         = { "gems", "enchant", "ilevel", "upgrade" },
        HandsSlot         = { "gems", "enchant", "ilevel", "upgrade" },
        WaistSlot         = { "gems",            "ilevel", "waistEnchant", "upgrade" },
        LegsSlot          = { "gems", "enchant", "ilevel", "upgrade" },
        FeetSlot          = { "gems", "enchant", "ilevel", "upgrade" },
        Finger0Slot       = { "gems",            "ilevel", "upgrade" },
        Finger1Slot       = { "gems",            "ilevel", "upgrade" },
        MainHandSlot      = { "gems", "enchant", "ilevel", "upgrade" },
        --SecondaryHandSlot = { "gems", "enchant", "ilevel", "upgrade" },
        Trinket0Slot      = { "gems",            "ilevel", "upgrade" },
        Trinket1Slot      = { "gems",            "ilevel", "upgrade" },
    }

    if self:IsTwoHandedOrRangedWeaponEquipped(playerInfo) then
        -- Use Hearthstone as a placeholder for the secondary hand slot.
        playerInfo.EquippedItems = playerInfo.EquippedItems or {}
        local _, placeholderLink = GetItemInfo(6948)
        playerInfo.EquippedItems["SecondaryHandSlot"] = placeholderLink
    else
        slotConfig.SecondaryHandSlot = { "gems", "enchant", "ilevel", "upgrade" }
    end

    for slotName, slotChecks in pairs(slotConfig) do
        for _, checkKey in ipairs(slotChecks) do
            local checkData = checks[checkKey]
            playerInfo.pendingChecks = playerInfo.pendingChecks + 1
            self:CheckItemSlotWithRetry(playerInfo, slotName, checkData.func, checkData.message, nil, function()
                playerInfo.pendingChecks = playerInfo.pendingChecks - 1
                if playerInfo.pendingChecks <= 0 then
                    onComplete(playerInfo)
                end
            end)
        end
    end

    -- In case no checks were scheduled, complete immediately.
    if playerInfo.pendingChecks == 0 then
        onComplete(playerInfo)
    end
end
