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
        reportableItems = {},
        totalProblemCount = 0,
        hasProblems = false,
    }
    local reportableItemsByKey = {}

    for _, problem in ipairs(Problems.GetRecords(playerInfo)) do
        if IsValidProblem(problem) then
            table.insert(index.orderedRecords, problem)
            index.totalProblemCount = index.totalProblemCount + 1
            index.hasProblems = true

            if problem.slotName then
                index.bySlot[problem.slotName] = index.bySlot[problem.slotName] or {}
                table.insert(index.bySlot[problem.slotName], problem)
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
    end

    return index
end
