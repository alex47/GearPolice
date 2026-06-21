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

function Inspection:IsItemMetadataPending(checkResult)
    return checkResult == GearPolice.ItemMetadataPending
end

function Inspection:MarkItemMetadataPending(playerInfo, slotName, itemLink, scanGeneration)
    if not self:IsCurrentScan(playerInfo, scanGeneration) then
        return false
    end

    playerInfo.PendingItemMetadata = playerInfo.PendingItemMetadata or {}
    playerInfo.PendingItemMetadata[slotName] = itemLink or true
    return true
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
            return GearPolice.ItemMetadataPending
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
        return GearPolice.ItemMetadataPending
    end

    if socketSlotCount == 0 then
        return false
    end

    if socketSlotCount > 4 then
        return GearPolice.ItemMetadataPending
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
        return GearPolice.ItemMetadataPending
    end

    return itemLevel < ItemLevelThreshold
end

function Inspection:IsWaistMissingExtraGemEnchant(itemLink)
    if not itemLink then return false end

    local base = self:CountSocketSlots(itemLink)
    if self:IsItemMetadataPending(base) then
        return GearPolice.ItemMetadataPending
    end

    if base == 0 then return false end

    local inserted = self:CountSocketedGemIds(itemLink, 4)

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
    if not equipLoc then
        return GearPolice.ItemMetadataPending
    end

    return equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_RANGED"
end

function Inspection:ResolveInventorySlotWithRetry(
    playerInfo,
    slotName,
    retryCount,
    onResolved,
    noEvidenceCount,
    scanGeneration
)
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
    local slotState, itemLink, slotID
    if unitId then
        slotState, itemLink, slotID = GearPolice.Helper:GetInventorySlotState(unitId, slotName)
    else
        slotState = GearPolice.InventorySlotPending
    end

    if slotState == GearPolice.InventorySlotReady then
        if not self:SetEquippedSlotValue(playerInfo, slotName, itemLink, scanGeneration) then
            return
        end
        onResolved(slotName, itemLink, slotID)
        return
    end

    if slotState == GearPolice.InventorySlotNoEvidence then
        noEvidenceCount = noEvidenceCount + 1
        if self:CanConfirmEmptyInventorySlot(playerInfo, unitId, slotName, noEvidenceCount) then
            if not self:SetEquippedSlotValue(playerInfo, slotName, GearPolice.InventorySlotEmpty, scanGeneration) then
                return
            end
            onResolved(slotName, GearPolice.InventorySlotEmpty, slotID)
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
        onResolved(slotName, GearPolice.InventorySlotPending, slotID)
        return
    end

    local delay = InspectionRetryDelay()
    GearPolice:ScheduleManagedTimer(function()
        Inspection:ResolveInventorySlotWithRetry(
            playerInfo,
            slotName,
            retryCount - 1,
            onResolved,
            noEvidenceCount,
            scanGeneration
        )
    end, delay, playerInfo.PlayerGuid)
end

function Inspection:ApplySlotChecks(playerInfo, slotName, slotValue, slotID, checks, slotConfig, scanGeneration)
    if not self:IsCurrentScan(playerInfo, scanGeneration) or not self:IsStoredItemLink(slotValue) then
        return
    end

    local slotChecks = slotConfig[slotName]
    if not slotChecks then
        return
    end

    local unitId = GearPolice.Helper:GetUnitIdOfPlayerGuid(playerInfo.PlayerGuid)
    for _, checkKey in ipairs(slotChecks) do
        local checkData = checks[checkKey]
        if checkData then
            local checkResult = checkData.func(slotValue, unitId, slotID)
            if self:IsItemMetadataPending(checkResult) then
                self:MarkItemMetadataPending(playerInfo, slotName, slotValue, scanGeneration)
            elseif checkResult then
                if not playerInfo.ProblematicItems[slotValue] then
                    playerInfo.ProblematicItems[slotValue] = {}
                end
                table.insert(playerInfo.ProblematicItems[slotValue], checkData.message)
            end
        end
    end
end

function Inspection:CheckUnit(playerInfo, onComplete, scanGeneration)
    -- Reset problematic items and initialize the pending checks counter.
    playerInfo.ProblematicItems = {}
    playerInfo.PendingItemMetadata = {}
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
        SecondaryHandSlot = { "gems", "enchant", "ilevel", "upgrade" },
        Trinket0Slot      = { "gems",            "ilevel", "upgrade" },
        Trinket1Slot      = { "gems",            "ilevel", "upgrade" },
    }

    local totalSlots = 0
    local completedSlots = 0
    local isSchedulingSlots = true
    local isUnitCheckComplete = false

    local function CompleteUnitCheckIfReady()
        if not isSchedulingSlots and not isUnitCheckComplete and completedSlots >= totalSlots then
            isUnitCheckComplete = true
            playerInfo.pendingChecks = 0
            onComplete(playerInfo)
        end
    end

    local function CompleteSlot(slotName, slotValue, slotID)
        if isUnitCheckComplete or not self:IsCurrentScan(playerInfo, scanGeneration) then
            return false
        end

        self:ApplySlotChecks(playerInfo, slotName, slotValue, slotID, checks, slotConfig, scanGeneration)

        completedSlots = completedSlots + 1
        playerInfo.pendingChecks = totalSlots - completedSlots
        if playerInfo.pendingChecks < 0 then
            playerInfo.pendingChecks = 0
        end

        CompleteUnitCheckIfReady()
        return true
    end

    local function ScheduleSlotResolution(slotName, onResolved)
        local slotChecks = slotConfig[slotName]
        if not slotChecks then
            return false
        end

        totalSlots = totalSlots + 1
        playerInfo.pendingChecks = totalSlots - completedSlots
        self:ResolveInventorySlotWithRetry(playerInfo, slotName, nil, function(resolvedSlotName, slotValue, slotID)
            if CompleteSlot(resolvedSlotName, slotValue, slotID) and onResolved then
                onResolved(slotValue)
            end
        end, nil, scanGeneration)
        return true
    end

    local function ScheduleRemainingSlots(mainHandValue)
        if isUnitCheckComplete or not self:IsCurrentScan(playerInfo, scanGeneration) then
            return
        end

        local skipSecondaryHand = self:IsTwoHandedOrRangedWeaponLink(mainHandValue)
        if self:IsItemMetadataPending(skipSecondaryHand) then
            self:MarkItemMetadataPending(playerInfo, "MainHandSlot", mainHandValue, scanGeneration)
            skipSecondaryHand = false
        end

        if skipSecondaryHand then
            self:SetEquippedSlotValue(
                playerInfo,
                "SecondaryHandSlot",
                GearPolice.InventorySlotEmpty,
                scanGeneration
            )
        end

        for _, slotName in ipairs(GearPolice.Helper:GetInventorySlotNames()) do
            if slotName ~= "MainHandSlot"
                and (slotName ~= "SecondaryHandSlot" or not skipSecondaryHand) then
                ScheduleSlotResolution(slotName)
            end
        end

        isSchedulingSlots = false
        CompleteUnitCheckIfReady()
    end

    local scheduledMainHand = ScheduleSlotResolution("MainHandSlot", function(mainHandValue)
        ScheduleRemainingSlots(mainHandValue)
    end)

    if not scheduledMainHand then
        isSchedulingSlots = false
        CompleteUnitCheckIfReady()
    end
end
