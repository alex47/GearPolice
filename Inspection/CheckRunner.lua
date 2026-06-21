local GearPolice = GearPolice

local Inspection = GearPolice.Inspection

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
        if rule then
            local checkResult = rule.evaluate(slotValue, context)
            if self:IsItemMetadataPending(checkResult) then
                self:MarkItemMetadataPending(playerInfo, slotName, slotValue, scanGeneration)
            elseif checkResult then
                self:RecordProblem(playerInfo, slotName, slotValue, ruleId, rule.message, scanGeneration)
            end
        end
    end
end

function Inspection:CheckUnit(playerInfo, onComplete, scanGeneration)
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

    local function ScheduleSlotResolution(slotName, onResolved)
        local slotRuleIds = GearPolice.Rules.GetSlotRuleIdsForSlot(slotName)
        if not slotRuleIds then
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
