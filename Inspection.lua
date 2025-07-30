local GearPolice = GearPolice

GearPolice.Inspection = GearPolice.Inspection or {}
local Inspection = GearPolice.Inspection

local ItemLevelThreshold = 450


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

    local gem1, gem2, gem3, gem4 = select(4, strsplit(":", itemLink))

    local socketedGemCount = 0

    if (gem1 ~= "") then
        socketedGemCount = socketedGemCount + 1
    end

    if (gem2 ~= "") then
        socketedGemCount = socketedGemCount + 1
    end

    if (gem3 ~= "") then
        socketedGemCount = socketedGemCount + 1
    end

    if (gem4 ~= "") then
        socketedGemCount = socketedGemCount + 1
    end

    return socketedGemCount < gemSlotCount
end

function Inspection:IsItemMissingEnchant(itemLink)
    if not itemLink then 
        return false 
    end

    local enchantID = select(3, strsplit(":", itemLink))

    return enchantID == ""
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
    return false
end

function Inspection:CheckItemSlotWithRetry(playerInfo, slotName, itemCheckFunction, message, retryCount, onComplete)
    if not retryCount then
        retryCount = 1024
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
        if itemCheckFunction(itemLink) then
            if not playerInfo.ProblematicItems[itemLink] then
                playerInfo.ProblematicItems[itemLink] = {}
            end
            table.insert(playerInfo.ProblematicItems[itemLink], message)
        end
        onComplete()
    else
        local texture = GetInventoryItemTexture(unitId, slotID)
        if texture then
            -- An item is equipped (texture exists) but its link isn't available yet; retry.
            C_Timer.After(10, function()
                Inspection:CheckItemSlotWithRetry(playerInfo, slotName, itemCheckFunction, message, retryCount - 1, onComplete)
            end)
        else
            -- No item is equipped in this slot.
            onComplete()
        end
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
            message = "Missing Extra Waist gem enchant"
        },
        ilevel = {
            func = function(itemLink) return self:IsItemBelowItemLevel(itemLink) end,
            message = "Low item level"
        },
    }

    local slotConfig = {
        --HeadSlot          = { "gems", "enchant", "ilevel" }, -- Remove head enchant temporarily as there aren't any in the game yet as of MoP Phase 1.
        HeadSlot          = { "gems",            "ilevel" },
        NeckSlot          = { "gems",            "ilevel" },
        ShoulderSlot      = { "gems", "enchant", "ilevel" },
        BackSlot          = { "gems", "enchant", "ilevel" },
        ChestSlot         = { "gems", "enchant", "ilevel" },
        WristSlot         = { "gems", "enchant", "ilevel" },
        HandsSlot         = { "gems", "enchant", "ilevel" },
        WaistSlot         = { "gems",            "ilevel" },
        LegsSlot          = { "gems", "enchant", "ilevel" },
        FeetSlot          = { "gems", "enchant", "ilevel" },
        Finger0Slot       = { "gems",            "ilevel" },
        Finger1Slot       = { "gems",            "ilevel" },
        MainHandSlot      = { "gems", "enchant", "ilevel" },
        --SecondaryHandSlot = { "gems", "enchant", "ilevel" },
        Trinket0Slot      = { "gems",            "ilevel" },
        Trinket1Slot      = { "gems",            "ilevel" },
    }

    if self:IsTwoHandedOrRangedWeaponEquipped(playerInfo) then
        -- Use Hearthstone as a placeholder for the secondary hand slot.
        playerInfo.EquippedItems = playerInfo.EquippedItems or {}
        local _, placeholderLink = GetItemInfo(6948)
        playerInfo.EquippedItems["SecondaryHandSlot"] = placeholderLink
    else
        slotConfig.SecondaryHandSlot = { "gems", "enchant", "ilevel" }
    end

    for slotName, slotChecks in pairs(slotConfig) do
        for _, checkKey in ipairs(slotChecks) do
            local checkData = checks[checkKey]
            playerInfo.pendingChecks = playerInfo.pendingChecks + 1
            self:CheckItemSlotWithRetry(playerInfo, slotName, checkData.func, checkData.message, 5, function()
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
