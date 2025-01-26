local GearPolice = GearPolice

GearPolice.Inspection = GearPolice.Inspection or {}
local Inspection = GearPolice.Inspection

local ItemLevelThreshold = 346


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

function Inspection:CheckItemSlotWithRetry(playerInfo, slotName, itemCheckFunction, message, retryCount)
    if not retryCount then
        retryCount = 5
    end

    if retryCount <= 0 then
        -- Max retries reached; assume scan failed for this slot
        GearPolice.Debug:Message("Failed to inspect " .. slotName .. " for " .. playerInfo.PlayerName)
        return
    end

    local unitId = GearPolice.Helper:GetUnitIdOfPlayerGuid(playerInfo.PlayerGuid)

    if not unitId then
        return
    end

    -- Do the item checking
    local itemLink = GetInventoryItemLink(unitId, GetInventorySlotInfo(slotName))

    if itemLink then
        if itemCheckFunction(itemLink) then
            if not playerInfo.ProblematicItems[itemLink] then
                playerInfo.ProblematicItems[itemLink] = {}
            end

            table.insert(playerInfo.ProblematicItems[itemLink], message)
        end
    else
        -- Item link is nil; retry after delay
        C_Timer.After(2, function()
            Inspection:CheckItemSlotWithRetry(playerInfo, slotName, itemCheckFunction, message, retryCount - 1)
        end)
    end

    GearPolice.UI:UpdateUI()
end

function Inspection:CheckUnit(playerInfo)
    playerInfo.ProblematicItems = {}

    local messageGem = "Missing Gem"
    local messageEnchant = "Missing Enchant"
    local messageItemLevel = "Low item level"

    Inspection:CheckItemSlotWithRetry(playerInfo, "HeadSlot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "HeadSlot", function(itemLink) return Inspection:IsItemMissingEnchant(itemLink) end, messageEnchant)
    Inspection:CheckItemSlotWithRetry(playerInfo, "HeadSlot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)

    Inspection:CheckItemSlotWithRetry(playerInfo, "NeckSlot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "NeckSlot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)
    
    Inspection:CheckItemSlotWithRetry(playerInfo, "ShoulderSlot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "ShoulderSlot", function(itemLink) return Inspection:IsItemMissingEnchant(itemLink) end, messageEnchant)
    Inspection:CheckItemSlotWithRetry(playerInfo, "ShoulderSlot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)
    
    Inspection:CheckItemSlotWithRetry(playerInfo, "BackSlot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "BackSlot", function(itemLink) return Inspection:IsItemMissingEnchant(itemLink) end, messageEnchant)
    Inspection:CheckItemSlotWithRetry(playerInfo, "BackSlot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)
    
    Inspection:CheckItemSlotWithRetry(playerInfo, "ChestSlot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "ChestSlot", function(itemLink) return Inspection:IsItemMissingEnchant(itemLink) end, messageEnchant)
    Inspection:CheckItemSlotWithRetry(playerInfo, "ChestSlot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)
    
    Inspection:CheckItemSlotWithRetry(playerInfo, "WristSlot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "WristSlot", function(itemLink) return Inspection:IsItemMissingEnchant(itemLink) end, messageEnchant)
    Inspection:CheckItemSlotWithRetry(playerInfo, "WristSlot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)
    
    Inspection:CheckItemSlotWithRetry(playerInfo, "HandsSlot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "HandsSlot", function(itemLink) return Inspection:IsItemMissingEnchant(itemLink) end, messageEnchant)
    Inspection:CheckItemSlotWithRetry(playerInfo, "HandsSlot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)
    
    Inspection:CheckItemSlotWithRetry(playerInfo, "WaistSlot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "WaistSlot", function(itemLink) return Inspection:IsWaistMissingExtraGemEnchant(itemLink) end, "Missing Extra Waist gem enchant")
    Inspection:CheckItemSlotWithRetry(playerInfo, "WaistSlot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)
    
    Inspection:CheckItemSlotWithRetry(playerInfo, "LegsSlot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "LegsSlot", function(itemLink) return Inspection:IsItemMissingEnchant(itemLink) end, messageEnchant)
    Inspection:CheckItemSlotWithRetry(playerInfo, "LegsSlot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)
    
    Inspection:CheckItemSlotWithRetry(playerInfo, "FeetSlot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "FeetSlot", function(itemLink) return Inspection:IsItemMissingEnchant(itemLink) end, messageEnchant)
    Inspection:CheckItemSlotWithRetry(playerInfo, "FeetSlot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)

    Inspection:CheckItemSlotWithRetry(playerInfo, "Finger0Slot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "Finger0Slot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)

    Inspection:CheckItemSlotWithRetry(playerInfo, "Finger1Slot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "Finger1Slot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)

    Inspection:CheckItemSlotWithRetry(playerInfo, "MainHandSlot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "MainHandSlot", function(itemLink) return Inspection:IsItemMissingEnchant(itemLink) end, messageEnchant)
    Inspection:CheckItemSlotWithRetry(playerInfo, "MainHandSlot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)
    
    Inspection:CheckItemSlotWithRetry(playerInfo, "SecondaryHandSlot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem, 1)
    Inspection:CheckItemSlotWithRetry(playerInfo, "SecondaryHandSlot", function(itemLink) return Inspection:IsItemMissingEnchant(itemLink) end, messageEnchant, 1)
    Inspection:CheckItemSlotWithRetry(playerInfo, "SecondaryHandSlot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)

    Inspection:CheckItemSlotWithRetry(playerInfo, "RangedSlot", function(itemLink) return Inspection:IsItemMissingGems(itemLink) end, messageGem)
    Inspection:CheckItemSlotWithRetry(playerInfo, "RangedSlot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)
    
    Inspection:CheckItemSlotWithRetry(playerInfo, "Trinket0Slot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)
    Inspection:CheckItemSlotWithRetry(playerInfo, "Trinket1Slot", function(itemLink) return Inspection:IsItemBelowItemLevel(itemLink) end, messageItemLevel)
end
