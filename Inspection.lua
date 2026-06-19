local GearPolice = GearPolice

GearPolice.Inspection = GearPolice.Inspection or {}
local Inspection = GearPolice.Inspection

local ItemLevelThreshold = 450


local function InspectionRetryDelay()
    return GearPolice.InventorySlotRetryDelay
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
    -- Short-circuit upgrade checks; treat every item as fully upgraded.
    return false
end

function Inspection:CheckItemSlotWithRetry(playerInfo, slotName, itemCheckFunction, message, retryCount, onComplete, noEvidenceCount)
    if not retryCount then
        retryCount = GearPolice.InventorySlotRetryCount
    end

    if not noEvidenceCount then
        noEvidenceCount = 0
    end

    local unitId = GearPolice.Helper:GetUnitIdOfPlayerGuid(playerInfo.PlayerGuid)
    if not unitId then
        onComplete()
        return
    end

    local slotState, itemLink, slotID = GearPolice.Helper:GetInventorySlotState(unitId, slotName)

    if slotState == GearPolice.InventorySlotReady then
        if itemCheckFunction(itemLink, unitId, slotID) then
            if not playerInfo.ProblematicItems[itemLink] then
                playerInfo.ProblematicItems[itemLink] = {}
            end
            table.insert(playerInfo.ProblematicItems[itemLink], message)
        end
        onComplete()
        return
    end

    if slotState == GearPolice.InventorySlotNoEvidence then
        noEvidenceCount = noEvidenceCount + 1
        if GearPolice.Helper:CanConfirmEmptyInventorySlot(unitId, slotName, noEvidenceCount) then
            onComplete()
            return
        end
    else
        noEvidenceCount = 0
    end

    if retryCount <= 0 then
        GearPolice.Debug:Message("Unable to confirm " .. slotName .. " for " .. playerInfo.PlayerName)
        onComplete()
        return
    end

    local delay = InspectionRetryDelay()
    GearPolice:ScheduleManagedTimer(function()
        Inspection:CheckItemSlotWithRetry(playerInfo, slotName, itemCheckFunction, message, retryCount - 1, onComplete, noEvidenceCount)
    end, delay)
end

function Inspection:IsTwoHandedOrRangedWeaponEquipped(playerInfo)
    local unitId = GearPolice.Helper:GetUnitIdOfPlayerGuid(playerInfo.PlayerGuid)
    if not unitId then return false end

    local slotState, link = GearPolice.Helper:GetInventorySlotState(unitId, "MainHandSlot")
    if slotState ~= GearPolice.InventorySlotReady then return nil end

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
        playerInfo.EquippedItems = playerInfo.EquippedItems or {}
        playerInfo.EquippedItems["SecondaryHandSlot"] = GearPolice.InventorySlotEmpty
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
