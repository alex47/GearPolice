local GearPolice = GearPolice

GearPolice.Problems = GearPolice.Problems or {}

local Problems = GearPolice.Problems

local function IsValidProblem(problem)
    return type(problem) == "table"
        and type(problem.itemLink) == "string"
        and problem.itemLink ~= ""
        and type(problem.message) == "string"
        and problem.message ~= ""
end

local function BuildLegacySignature(itemLink, message)
    return itemLink .. "\001" .. message
end

local function BuildOrderedProblems(playerInfo)
    local orderedProblems = {}

    for originalIndex, problem in ipairs(Problems.GetRecords(playerInfo)) do
        if IsValidProblem(problem) then
            table.insert(orderedProblems, {
                problem = problem,
                originalIndex = originalIndex,
                slotOrder = GearPolice.Slots.GetSlotOrder(problem.slotName),
                ruleOrder = GearPolice.Rules.GetIssueSummaryOrder(problem.ruleId),
            })
        end
    end

    table.sort(orderedProblems, function(left, right)
        local leftHasKnownSlot = left.slotOrder ~= nil
        local rightHasKnownSlot = right.slotOrder ~= nil
        if leftHasKnownSlot ~= rightHasKnownSlot then
            return leftHasKnownSlot
        end

        if leftHasKnownSlot and left.slotOrder ~= right.slotOrder then
            return left.slotOrder < right.slotOrder
        end

        local leftProblem = left.problem
        local rightProblem = right.problem
        if leftProblem.itemLink ~= rightProblem.itemLink then
            return leftProblem.itemLink < rightProblem.itemLink
        end

        local leftRuleOrder = left.ruleOrder or math.huge
        local rightRuleOrder = right.ruleOrder or math.huge
        if leftRuleOrder ~= rightRuleOrder then
            return leftRuleOrder < rightRuleOrder
        end

        local leftMessage = string.lower(leftProblem.message)
        local rightMessage = string.lower(rightProblem.message)
        if leftMessage ~= rightMessage then
            return leftMessage < rightMessage
        end

        if leftProblem.message ~= rightProblem.message then
            return leftProblem.message < rightProblem.message
        end

        return left.originalIndex < right.originalIndex
    end)

    return orderedProblems
end

function Problems.Add(playerInfo, problem)
    if type(playerInfo) ~= "table" or not IsValidProblem(problem) then
        return false
    end

    playerInfo.Problems = playerInfo.Problems or {}
    table.insert(playerInfo.Problems, {
        slotName = problem.slotName,
        itemLink = problem.itemLink,
        ruleId = problem.ruleId,
        message = problem.message,
    })
    return true
end

function Problems.NormalizeStoredPlayer(playerInfo)
    if type(playerInfo) ~= "table" then
        return false
    end

    local normalizedProblems = {}
    local structuredCounts = {}

    if type(playerInfo.Problems) == "table" then
        for _, problem in ipairs(playerInfo.Problems) do
            if IsValidProblem(problem) then
                local normalizedProblem = {
                    slotName = problem.slotName,
                    itemLink = problem.itemLink,
                    ruleId = problem.ruleId,
                    message = problem.message,
                }
                table.insert(normalizedProblems, normalizedProblem)

                local signature = BuildLegacySignature(problem.itemLink, problem.message)
                structuredCounts[signature] = (structuredCounts[signature] or 0) + 1
            end
        end
    end

    if type(playerInfo.ProblematicItems) == "table" then
        local matchedStructuredCounts = {}

        for itemLink, legacyProblems in pairs(playerInfo.ProblematicItems) do
            local messages = type(legacyProblems) == "table" and legacyProblems or { legacyProblems }
            for _, message in ipairs(messages) do
                if type(itemLink) == "string" and itemLink ~= ""
                    and type(message) == "string" and message ~= "" then
                    local signature = BuildLegacySignature(itemLink, message)
                    local matchedCount = matchedStructuredCounts[signature] or 0
                    local structuredCount = structuredCounts[signature] or 0

                    if matchedCount < structuredCount then
                        matchedStructuredCounts[signature] = matchedCount + 1
                    else
                        table.insert(normalizedProblems, {
                            itemLink = itemLink,
                            message = message,
                        })
                    end
                end
            end
        end
    end

    playerInfo.Problems = normalizedProblems
    playerInfo.ProblematicItems = nil
    return true
end

function Problems.GetRecords(playerInfo)
    if type(playerInfo) ~= "table" then
        return {}
    end

    if playerInfo.ProblematicItems ~= nil then
        Problems.NormalizeStoredPlayer(playerInfo)
    elseif type(playerInfo.Problems) ~= "table" then
        playerInfo.Problems = {}
    end

    return playerInfo.Problems
end

function Problems.BuildIndex(playerInfo)
    local index = {
        orderedRecords = {},
        bySlot = {},
        byItemLink = {},
        unownedByItemLink = {},
        reportableItems = {},
        totalProblemCount = 0,
        hasProblems = false,
    }
    local reportableItemsByKey = {}

    for _, orderedProblem in ipairs(BuildOrderedProblems(playerInfo)) do
        local problem = orderedProblem.problem
        table.insert(index.orderedRecords, problem)
        index.totalProblemCount = index.totalProblemCount + 1
        index.hasProblems = true

        if problem.slotName then
            index.bySlot[problem.slotName] = index.bySlot[problem.slotName] or {}
            table.insert(index.bySlot[problem.slotName], problem)
        else
            index.unownedByItemLink[problem.itemLink] =
                index.unownedByItemLink[problem.itemLink] or {}
            table.insert(index.unownedByItemLink[problem.itemLink], problem)
        end

        index.byItemLink[problem.itemLink] = index.byItemLink[problem.itemLink] or {}
        table.insert(index.byItemLink[problem.itemLink], problem)

        local key = tostring(problem.slotName or "") .. "\001" .. problem.itemLink
        local reportableItem = reportableItemsByKey[key]
        if not reportableItem then
            reportableItem = {
                itemLink = problem.itemLink,
                slotName = problem.slotName,
                problems = {},
                problemRecords = {},
            }
            reportableItemsByKey[key] = reportableItem
            table.insert(index.reportableItems, reportableItem)
        end

        table.insert(reportableItem.problems, problem.message)
        table.insert(reportableItem.problemRecords, problem)
    end

    return index
end
