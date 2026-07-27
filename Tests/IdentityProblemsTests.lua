return function(Harness, suite)
    local function LoadPlayers(unitData)
        local environment
        environment = Harness.MakeEnvironment({
            GearPolice = {},
            UNKNOWNOBJECT = "Unknown object",
            UNKNOWN = "Unknown",
            UnitExists = function(unitId)
                return unitData[unitId] ~= nil
            end,
            UnitGUID = function(unitId)
                local unit = unitData[unitId]
                return unit and unit.guid or nil
            end,
            UnitFullName = function(unitId)
                local unit = unitData[unitId]
                return unit and unit.fullName or nil, unit and unit.realm or nil
            end,
            UnitName = function(unitId)
                local unit = unitData[unitId]
                return unit and unit.name or nil, unit and unit.realm or nil
            end,
            GetRealmName = function()
                return "Home Realm"
            end,
        })
        Harness.LoadModule(suite, environment, "Util/Players.lua")
        return environment
    end

    Harness.Add(suite, "player identity rejects every unknown-name form", function()
        local environment = LoadPlayers({})
        local players = environment.GearPolice.Players

        Harness.AssertFalse(players.IsKnownName(nil))
        Harness.AssertFalse(players.IsKnownName(""))
        Harness.AssertFalse(players.IsKnownName("Unknown"))
        Harness.AssertFalse(players.IsKnownName("Unknown Player"))
        Harness.AssertFalse(players.IsKnownName(environment.UNKNOWNOBJECT))
        Harness.AssertTrue(players.IsKnownName("Borlandc"))
    end)

    Harness.Add(suite, "unit full names cover same-realm and cross-realm players", function()
        local environment = LoadPlayers({
            same = {
                guid = "Player-1-SAME",
                name = "Alpha",
                fullName = "Alpha",
            },
            cross = {
                guid = "Player-2-CROSS",
                name = "Beta",
                fullName = "Beta",
                realm = "Other Realm",
            },
        })
        local players = environment.GearPolice.Players

        Harness.AssertEqual("Alpha-Home Realm", players.GetUnitFullName("same"))
        Harness.AssertEqual("Beta-Other Realm", players.GetUnitFullName("cross"))
        Harness.AssertEqual(
            "Alpha-Home Realm",
            players.GetWhisperRecipient({
                PlayerGuid = "Player-1-SAME",
                CurrentUnitId = "same",
                PlayerFullName = "Old-Other",
            })
        )
        Harness.AssertEqual(
            "Stored-Realm",
            players.GetWhisperRecipient({
                PlayerGuid = "Player-9-STORED",
                CurrentUnitId = "same",
                PlayerFullName = "Stored-Realm",
            })
        )
    end)

    local function LoadProblems()
        local environment = Harness.MakeEnvironment({
            GearPolice = {
                Inspection = {},
                Settings = {
                    GetItemLevelThreshold = function()
                        return 450
                    end,
                },
            },
            GetItemInfo = function()
                return nil
            end,
        })

        Harness.LoadModule(suite, environment, "Config/Constants.lua")
        Harness.LoadModule(suite, environment, "Config/Slots.lua")
        Harness.LoadModule(suite, environment, "Config/Rules.lua")
        Harness.LoadModule(suite, environment, "State/Problems.lua")
        return environment
    end

    Harness.Add(suite, "structured problems stay owned by their equipment slot", function()
        local environment = LoadProblems()
        local gearPolice = environment.GearPolice
        local itemLink = "|cffa335ee|Hitem:1::::::::|h[Same Ring]|h|r"
        local playerInfo = {
            Problems = {
                {
                    slotName = "Finger0Slot",
                    itemLink = itemLink,
                    ruleId = "missing_gems",
                    message = "Missing Gem",
                },
            },
            EquippedItems = {
                Finger0Slot = itemLink,
                Finger1Slot = itemLink,
            },
        }
        local index = gearPolice.Problems.BuildIndex(playerInfo)

        Harness.AssertEqual(1, #index.bySlot.Finger0Slot)
        Harness.AssertEqual(nil, index.bySlot.Finger1Slot)
        Harness.AssertEqual(nil, index.unownedByItemLink[itemLink])

        gearPolice.UI = {
            QuestionMarkIcon = "question",
            GetCheckStatusTexture = function()
                return "status"
            end,
        }
        gearPolice.PlayerStore = {
            GetAll = function()
                return {}
            end,
        }
        gearPolice.Settings.PlayerListFilter = {
            Problems = "problems",
            Scanning = "scanning",
            FailedPartial = "failed_partial",
        }
        Harness.LoadModule(suite, environment, "UI/ViewModel.lua")

        local firstRing = gearPolice.UI.ViewModel.BuildSlot(
            playerInfo,
            "Finger0Slot",
            index
        )
        local secondRing = gearPolice.UI.ViewModel.BuildSlot(
            playerInfo,
            "Finger1Slot",
            index
        )
        Harness.AssertTrue(firstRing.isProblematic)
        Harness.AssertFalse(secondRing.isProblematic)
    end)

    Harness.Add(suite, "legacy nil-slot problems retain item-link fallback", function()
        local environment = LoadProblems()
        local gearPolice = environment.GearPolice
        local itemLink = "|cffa335ee|Hitem:2::::::::|h[Legacy Ring]|h|r"
        local playerInfo = {
            Problems = {
                {
                    itemLink = itemLink,
                    message = "Legacy Problem",
                },
            },
        }
        local index = gearPolice.Problems.BuildIndex(playerInfo)

        Harness.AssertEqual(1, index.totalProblemCount)
        Harness.AssertEqual(1, #index.byItemLink[itemLink])
        Harness.AssertEqual(1, #index.unownedByItemLink[itemLink])
    end)

    Harness.Add(suite, "problem indexing is deterministic without mutating saved order", function()
        local environment = LoadProblems()
        local gearPolice = environment.GearPolice
        local firstSavedProblem = {
            slotName = "LegsSlot",
            itemLink = "item:legs",
            ruleId = "missing_upgrade",
            message = "Missing Upgrade",
        }
        local playerInfo = {
            Problems = {
                firstSavedProblem,
                {
                    slotName = "HeadSlot",
                    itemLink = "item:head",
                    ruleId = "low_item_level",
                    message = "Low Item Level",
                },
                {
                    slotName = "HeadSlot",
                    itemLink = "item:head",
                    ruleId = "missing_gems",
                    message = "Missing Gem",
                },
            },
        }

        local index = gearPolice.Problems.BuildIndex(playerInfo)
        Harness.AssertEqual(firstSavedProblem, playerInfo.Problems[1])
        Harness.AssertEqual("Missing Gem", index.orderedRecords[1].message)
        Harness.AssertEqual("Low Item Level", index.orderedRecords[2].message)
        Harness.AssertEqual("Missing Upgrade", index.orderedRecords[3].message)
        Harness.AssertEqual(3, index.totalProblemCount)
    end)
end
