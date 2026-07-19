local GearPolice = GearPolice

local Inspection = GearPolice.Inspection
local EnchanterRingEnchantRuleId = "missing_enchanter_ring_enchant"
local EnchanterRingEnchantMessage = "Missing Enchanter Ring Enchant"

local function IsPendingSlotValue(slotValue)
    return not slotValue or slotValue == GearPolice.InventorySlotPending
end

local function IsEnchantedItemLink(itemLink)
    return Inspection:IsStoredItemLink(itemLink) and not Inspection:IsItemMissingEnchant(itemLink)
end

function Inspection:ApplySlotChecks(playerInfo, slotName, slotValue, slotID, scanGeneration)
    if not self:IsCurrentScan(playerInfo, scanGeneration) or not self:IsStoredItemLink(slotValue) then
        return
    end

    local slotRuleIds = GearPolice.Rules.GetSlotRuleIdsForSlot(slotName)
    if not slotRuleIds then
        return
    end

    local ruleDefinitions = GearPolice.Rules.GetRuleDefinitions()
    local unitId = GearPolice.Helper:GetUnitIdOfPlayerGuid(playerInfo.PlayerGuid)
    local context = {
        playerInfo = playerInfo,
        slotName = slotName,
        unitId = unitId,
        slotID = slotID,
    }

    for _, ruleId in ipairs(slotRuleIds) do
        local rule = ruleDefinitions[ruleId]
        if rule and GearPolice.Settings:IsRuleEnabled(ruleId) then
            local checkResult = rule.evaluate(slotValue, context)
            if self:IsItemMetadataPending(checkResult) then
                self:MarkItemMetadataPending(playerInfo, slotName, slotValue, scanGeneration)
            elseif checkResult then
                local problemMessage = rule.message
                if type(rule.buildMessage) == "function" then
                    problemMessage = rule.buildMessage(slotValue, context)
                end

                self:RecordProblem(playerInfo, slotName, slotValue, ruleId, problemMessage, scanGeneration)
            end
        end
    end
end

function Inspection:ApplyEnchanterRingChecks(playerInfo, scanGeneration)
    if not self:IsCurrentScan(playerInfo, scanGeneration) then
        return
    end

    if not GearPolice.Settings:IsRuleEnabled(EnchanterRingEnchantRuleId) then
        return
    end

    local equippedItems = playerInfo and playerInfo.EquippedItems
    if type(equippedItems) ~= "table" then
        return
    end

    local firstRing = equippedItems.Finger0Slot
    local secondRing = equippedItems.Finger1Slot
    if IsPendingSlotValue(firstRing) or IsPendingSlotValue(secondRing) then
        return
    end

    local firstRingIsEnchanted = IsEnchantedItemLink(firstRing)
    local secondRingIsEnchanted = IsEnchantedItemLink(secondRing)
    if not firstRingIsEnchanted and not secondRingIsEnchanted then
        return
    end

    if self:IsStoredItemLink(firstRing) and not firstRingIsEnchanted then
        self:RecordProblem(
            playerInfo,
            "Finger0Slot",
            firstRing,
            EnchanterRingEnchantRuleId,
            EnchanterRingEnchantMessage,
            scanGeneration
        )
    end

    if self:IsStoredItemLink(secondRing) and not secondRingIsEnchanted then
        self:RecordProblem(
            playerInfo,
            "Finger1Slot",
            secondRing,
            EnchanterRingEnchantRuleId,
            EnchanterRingEnchantMessage,
            scanGeneration
        )
    end
end

function Inspection:CheckUnit(playerInfo, onComplete, scanGeneration)
    if InCombatLockdown() then
        GearPolice:PauseCurrentScanForCombat(playerInfo.PlayerGuid, scanGeneration)
        return
    end

    playerInfo.ProblematicItems = {}
    playerInfo.Problems = {}
    playerInfo.PendingItemMetadata = {}
    playerInfo.pendingChecks = 0

    local totalSlots = 0
    local completedSlots = 0
    local isSchedulingSlots = true
    local isUnitCheckComplete = false

    local function CompleteUnitCheckIfReady()
        if not isSchedulingSlots and not isUnitCheckComplete and completedSlots >= totalSlots then
            isUnitCheckComplete = true
            self:ApplyEnchanterRingChecks(playerInfo, scanGeneration)
            playerInfo.pendingChecks = 0
            onComplete(playerInfo)
        end
    end

    local function CompleteSlot(slotName, slotValue, slotID)
        if isUnitCheckComplete or not self:IsCurrentScan(playerInfo, scanGeneration) then
            return false
        end

        self:ApplySlotChecks(playerInfo, slotName, slotValue, slotID, scanGeneration)

        completedSlots = completedSlots + 1
        playerInfo.pendingChecks = totalSlots - completedSlots
        if playerInfo.pendingChecks < 0 then
            playerInfo.pendingChecks = 0
        end

        CompleteUnitCheckIfReady()
        return true
    end

    local function ScheduleSlotResolution(slotName)
        local slotRuleIds = GearPolice.Rules.GetSlotRuleIdsForSlot(slotName)
        if not slotRuleIds then
            return false
        end

        totalSlots = totalSlots + 1
        playerInfo.pendingChecks = totalSlots - completedSlots
        self:ResolveInventorySlotWithRetry(playerInfo, slotName, nil, function(resolvedSlotName, slotValue, slotID)
            CompleteSlot(resolvedSlotName, slotValue, slotID)
        end, nil, scanGeneration)
        return true
    end

    for _, slotName in ipairs(GearPolice.Helper:GetInventorySlotNames()) do
        ScheduleSlotResolution(slotName)
    end

    isSchedulingSlots = false
    CompleteUnitCheckIfReady()
end
