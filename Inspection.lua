local GearPolice = GearPolice

GearPolice.Inspection = GearPolice.Inspection or {}
local Inspection = GearPolice.Inspection

local ItemLevelThreshold = 450


local function InspectionRetryDelay()
    return GearPolice.InventorySlotRetryDelay
end

function Inspection:IsCurrentScan(playerInfo, scanGeneration)
    return not scanGeneration or (playerInfo and playerInfo.ScanGeneration == scanGeneration)
end

function Inspection:IsStoredItemLink(slotValue)
    if not slotValue then
        return false
    end

    if slotValue == GearPolice.InventorySlotPending then
        return false
    end

    if slotValue == GearPolice.InventorySlotEmpty then
        return false
    end

    if slotValue == GearPolice.InventorySlotNoEvidence then
        return false
    end

    if slotValue == GearPolice.InventorySlotReady then
        return false
    end

    return true
end

function Inspection:SetEquippedSlotValue(playerInfo, slotName, slotValue, scanGeneration)
    if not self:IsCurrentScan(playerInfo, scanGeneration) then
        return false
    end

    playerInfo.EquippedItems = playerInfo.EquippedItems or {}
    local currentValue = playerInfo.EquippedItems[slotName]

    if slotValue == GearPolice.InventorySlotPending then
        if not currentValue or currentValue == GearPolice.InventorySlotPending then
            playerInfo.EquippedItems[slotName] = slotValue
        end
        return true
    end

    if slotValue == GearPolice.InventorySlotEmpty then
        if not currentValue or currentValue == GearPolice.InventorySlotPending or currentValue == GearPolice.InventorySlotEmpty then
            playerInfo.EquippedItems[slotName] = slotValue
        end
        return true
    end

    playerInfo.EquippedItems[slotName] = slotValue
    return true
end

function Inspection:GetCapturedInventoryEvidenceCount(playerInfo, excludedSlotName)
    if not playerInfo or type(playerInfo.EquippedItems) ~= "table" then
        return 0
    end

    local evidenceCount = 0
    for _, slotName in ipairs(GearPolice.Helper:GetInventorySlotNames()) do
        if slotName ~= excludedSlotName and self:IsStoredItemLink(playerInfo.EquippedItems[slotName]) then
            evidenceCount = evidenceCount + 1
        end
    end

    return evidenceCount
end

function Inspection:CanConfirmEmptyInventorySlot(playerInfo, unitId, slotName, noEvidenceCount)
    if GearPolice.Helper:CanConfirmEmptyInventorySlot(unitId, slotName, noEvidenceCount) then
        return true
    end

    if (noEvidenceCount or 0) < GearPolice.InventorySlotEmptyConfirmations then
        return false
    end

    local capturedEvidenceCount = self:GetCapturedInventoryEvidenceCount(playerInfo, slotName)
    return capturedEvidenceCount >= GearPolice.InventorySnapshotEvidenceMinimum
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

function Inspection:IsTwoHandedOrRangedWeaponLink(itemLink)
    if not itemLink then
        return false
    end

    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    return equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_RANGED"
end

function Inspection:CheckItemSlotWithRetry(playerInfo, slotName, itemCheckFunction, message, retryCount, onComplete, noEvidenceCount, scanGeneration)
    if not self:IsCurrentScan(playerInfo, scanGeneration) then
        return
    end

    if not retryCount then
        retryCount = GearPolice.InventorySlotRetryCount
    end

    if not noEvidenceCount then
        noEvidenceCount = 0
    end

    local unitId = GearPolice.Helper:GetUnitIdOfPlayerGuid(playerInfo.PlayerGuid)
    if not unitId then
        if not self:SetEquippedSlotValue(playerInfo, slotName, GearPolice.InventorySlotPending, scanGeneration) then
            return
        end
        onComplete()
        return
    end

    local slotState, itemLink, slotID = GearPolice.Helper:GetInventorySlotState(unitId, slotName)

    if slotState == GearPolice.InventorySlotReady then
        if not self:SetEquippedSlotValue(playerInfo, slotName, itemLink, scanGeneration) then
            return
        end

        if slotName == "MainHandSlot" and self:IsTwoHandedOrRangedWeaponLink(itemLink) then
            self:SetEquippedSlotValue(playerInfo, "SecondaryHandSlot", GearPolice.InventorySlotEmpty, scanGeneration)
        end

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
        if self:CanConfirmEmptyInventorySlot(playerInfo, unitId, slotName, noEvidenceCount) then
            if not self:SetEquippedSlotValue(playerInfo, slotName, GearPolice.InventorySlotEmpty, scanGeneration) then
                return
            end
            onComplete()
            return
        end
    else
        noEvidenceCount = 0
    end

    if retryCount <= 0 then
        if not self:SetEquippedSlotValue(playerInfo, slotName, GearPolice.InventorySlotPending, scanGeneration) then
            return
        end
        GearPolice.Debug:Message("Unable to confirm " .. slotName .. " for " .. playerInfo.PlayerName)
        onComplete()
        return
    end

    local delay = InspectionRetryDelay()
    GearPolice:ScheduleManagedTimer(function()
        Inspection:CheckItemSlotWithRetry(playerInfo, slotName, itemCheckFunction, message, retryCount - 1, onComplete, noEvidenceCount, scanGeneration)
    end, delay, playerInfo.PlayerGuid)
end

function Inspection:IsTwoHandedOrRangedWeaponEquipped(playerInfo)
    local unitId = GearPolice.Helper:GetUnitIdOfPlayerGuid(playerInfo.PlayerGuid)
    if not unitId then return false end

    local slotState, link = GearPolice.Helper:GetInventorySlotState(unitId, "MainHandSlot")
    if slotState ~= GearPolice.InventorySlotReady then return nil end

    return self:IsTwoHandedOrRangedWeaponLink(link)
end

function Inspection:CheckUnit(playerInfo, onComplete, scanGeneration)
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
        self:SetEquippedSlotValue(playerInfo, "SecondaryHandSlot", GearPolice.InventorySlotEmpty, scanGeneration)
    else
        slotConfig.SecondaryHandSlot = { "gems", "enchant", "ilevel", "upgrade" }
    end

    local totalChecks = 0
    local completedChecks = 0
    local isSchedulingChecks = true
    local isUnitCheckComplete = false

    local function CompleteCheck()
        if isUnitCheckComplete or not self:IsCurrentScan(playerInfo, scanGeneration) then
            return
        end

        completedChecks = completedChecks + 1
        playerInfo.pendingChecks = totalChecks - completedChecks
        if playerInfo.pendingChecks < 0 then
            playerInfo.pendingChecks = 0
        end

        if not isSchedulingChecks and completedChecks >= totalChecks then
            isUnitCheckComplete = true
            playerInfo.pendingChecks = 0
            onComplete(playerInfo)
        end
    end

    for _, slotName in ipairs(GearPolice.Helper:GetInventorySlotNames()) do
        local slotChecks = slotConfig[slotName]
        if slotChecks then
            for _, checkKey in ipairs(slotChecks) do
                local checkData = checks[checkKey]
                totalChecks = totalChecks + 1
                playerInfo.pendingChecks = totalChecks - completedChecks
                self:CheckItemSlotWithRetry(playerInfo, slotName, checkData.func, checkData.message, nil, function()
                    CompleteCheck()
                end, nil, scanGeneration)
            end
        end
    end

    isSchedulingChecks = false

    if totalChecks == 0 then
        isUnitCheckComplete = true
        onComplete(playerInfo)
    elseif completedChecks >= totalChecks then
        isUnitCheckComplete = true
        playerInfo.pendingChecks = 0
        onComplete(playerInfo)
    end
end
