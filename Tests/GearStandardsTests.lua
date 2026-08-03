return function(Harness, suite)
    local function Contains(values, expected)
        for _, value in ipairs(values or {}) do
            if value == expected then
                return true
            end
        end

        return false
    end

    local function LoadGearChecks()
        local itemData = {
            plate = {
                name = "Plate Chest",
                itemSubType = "Plate",
                itemClassId = 4,
                itemSubclassId = 4,
                stats = {
                    ITEM_MOD_STRENGTH_SHORT = 100,
                },
            },
            leather = {
                name = "Leather Chest",
                itemSubType = "Leather",
                itemClassId = 4,
                itemSubclassId = 2,
                stats = {
                    ITEM_MOD_AGILITY_SHORT = 100,
                },
            },
            intellectTrinket = {
                name = "Intellect Trinket",
                itemSubType = "Trinket",
                itemClassId = 4,
                itemSubclassId = 0,
                stats = {
                    ITEM_MOD_INTELLECT_SHORT = 100,
                },
            },
            strengthTrinket = {
                name = "Strength Trinket",
                itemSubType = "Trinket",
                itemClassId = 4,
                itemSubclassId = 0,
                stats = {
                    ITEM_MOD_STRENGTH_SHORT = 100,
                },
            },
            mixedTrinket = {
                name = "Mixed Trinket",
                itemSubType = "Trinket",
                itemClassId = 4,
                itemSubclassId = 0,
                stats = {
                    ITEM_MOD_STRENGTH_SHORT = 100,
                    ITEM_MOD_INTELLECT_SHORT = 100,
                },
            },
            statlessTrinket = {
                name = "Statless Trinket",
                itemSubType = "Trinket",
                itemClassId = 4,
                itemSubclassId = 0,
                stats = {},
            },
            cachedWithoutStats = {
                name = "Cached Item",
                itemSubType = "Trinket",
                itemClassId = 4,
                itemSubclassId = 0,
            },
            localizedFallback = {
                name = "Fallback Mail",
                itemSubType = "Mail",
                stats = {},
            },
            weapon = {
                name = "Weapon",
                itemSubType = "Sword",
                itemClassId = 2,
                itemSubclassId = 7,
                stats = {
                    ITEM_MOD_STRENGTH_SHORT = 100,
                },
            },
        }

        local environment = Harness.MakeEnvironment({
            GearPolice = {
                Inspection = {},
                Settings = {
                    GetItemLevelThreshold = function()
                        return 450
                    end,
                },
            },
            GetItemInfo = function(itemLink)
                local item = itemData[itemLink]
                if not item then
                    return nil
                end

                return item.name,
                    itemLink,
                    4,
                    500,
                    90,
                    "Armor",
                    item.itemSubType,
                    1,
                    "",
                    1,
                    0,
                    item.itemClassId,
                    item.itemSubclassId
            end,
            GetItemStats = function(itemLink, statTable)
                local item = itemData[itemLink]
                if not item or item.stats == nil then
                    return nil
                end

                statTable = statTable or {}
                for statKey, value in pairs(item.stats) do
                    statTable[statKey] = value
                end
                return statTable
            end,
        })

        Harness.LoadModule(suite, environment, "Config/Constants.lua")
        Harness.LoadModule(suite, environment, "Config/Slots.lua")
        Harness.LoadModule(suite, environment, "Config/GearStandards.lua")
        Harness.LoadModule(suite, environment, "Config/Rules.lua")
        Harness.LoadModule(suite, environment, "Inspection.lua")
        Harness.LoadModule(suite, environment, "Inspection/ItemChecks.lua")
        return environment
    end

    Harness.Add(suite, "preferred armor types cover every MoP class", function()
        local environment = LoadGearChecks()
        local standards = environment.GearPolice.GearStandards
        local expectedByClass = {
            DEATHKNIGHT = "Plate",
            DRUID = "Leather",
            HUNTER = "Mail",
            MAGE = "Cloth",
            MONK = "Leather",
            PALADIN = "Plate",
            PRIEST = "Cloth",
            ROGUE = "Leather",
            SHAMAN = "Mail",
            WARLOCK = "Cloth",
            WARRIOR = "Plate",
        }

        for classFile, expectedArmorType in pairs(expectedByClass) do
            Harness.AssertEqual(expectedArmorType, standards.GetPreferredArmorType(classFile))
        end
    end)

    Harness.Add(suite, "preferred primary stats cover every MoP specialization", function()
        local environment = LoadGearChecks()
        local standards = environment.GearPolice.GearStandards
        local primaryStat = standards.PrimaryStat
        local expectedByStat = {
            [primaryStat.Strength] = { 250, 251, 252, 66, 70, 71, 72, 73 },
            [primaryStat.Agility] = { 103, 104, 253, 254, 255, 268, 269, 259, 260, 261, 263 },
            [primaryStat.Intellect] = {
                102, 105, 62, 63, 64, 270, 65, 256, 257, 258, 262, 264, 265, 266, 267,
            },
        }

        for expectedPrimaryStat, specializationIds in pairs(expectedByStat) do
            for _, specializationId in ipairs(specializationIds) do
                Harness.AssertEqual(
                    expectedPrimaryStat,
                    standards.GetPreferredPrimaryStat(specializationId)
                )
            end
        end

        Harness.AssertEqual(primaryStat.Strength, standards.GetPreferredPrimaryStat(nil, "WARRIOR"))
        Harness.AssertEqual(nil, standards.GetPreferredPrimaryStat(nil, "PALADIN"))
    end)

    Harness.Add(suite, "new rules cover the intended equipment slots", function()
        local environment = LoadGearChecks()
        local gearPolice = environment.GearPolice

        for _, slotName in ipairs(gearPolice.Slots.GetInventorySlotNames()) do
            local ruleIds = gearPolice.Rules.GetSlotRuleIdsForSlot(slotName)
            Harness.AssertTrue(Contains(ruleIds, "incorrect_primary_stat"), slotName)
            Harness.AssertEqual(
                gearPolice.GearStandards.IsArmorSpecializationSlot(slotName),
                Contains(ruleIds, "incorrect_armor_type"),
                slotName
            )
        end

        Harness.AssertTrue(
            gearPolice.Rules.GetRuleDefinition("incorrect_armor_type").defaultEnabled
        )
        Harness.AssertTrue(
            gearPolice.Rules.GetRuleDefinition("incorrect_primary_stat").defaultEnabled
        )
    end)

    Harness.Add(suite, "armor checks report mismatches only at specialization level", function()
        local environment = LoadGearChecks()
        local gearPolice = environment.GearPolice
        local inspection = gearPolice.Inspection

        local incorrect = inspection:GetIncorrectArmorTypeResult("leather", {
            unitLevel = 90,
            expectedArmorType = "Plate",
        })
        Harness.AssertEqual("Leather", incorrect.actualArmorType)
        Harness.AssertEqual("Plate", incorrect.expectedArmorType)

        Harness.AssertFalse(inspection:GetIncorrectArmorTypeResult("plate", {
            unitLevel = 90,
            expectedArmorType = "Plate",
        }))
        Harness.AssertFalse(inspection:GetIncorrectArmorTypeResult("leather", {
            unitLevel = 49,
            expectedArmorType = "Plate",
        }))
        Harness.AssertFalse(inspection:GetIncorrectArmorTypeResult("weapon", {
            unitLevel = 90,
            expectedArmorType = "Plate",
        }))

        local fallback = inspection:GetIncorrectArmorTypeResult("localizedFallback", {
            unitLevel = 90,
            expectedArmorType = "Plate",
        })
        Harness.AssertEqual("Mail", fallback.actualArmorType)
        Harness.AssertEqual(
            gearPolice.Constants.ItemMetadataPending,
            inspection:GetIncorrectArmorTypeResult("missing", {
                unitLevel = 90,
                expectedArmorType = "Plate",
            })
        )
    end)

    Harness.Add(suite, "primary stat checks catch intellect trinkets on retribution paladins", function()
        local environment = LoadGearChecks()
        local gearPolice = environment.GearPolice
        local inspection = gearPolice.Inspection
        local strength = gearPolice.GearStandards.PrimaryStat.Strength
        local context = {
            unitLevel = 90,
            expectedPrimaryStat = strength,
        }

        local incorrect = inspection:GetIncorrectPrimaryStatResult("intellectTrinket", context)
        Harness.AssertEqual("Intellect", incorrect.actualPrimaryStatLabels[1])
        Harness.AssertEqual("Strength", incorrect.expectedPrimaryStatLabel)

        Harness.AssertFalse(
            inspection:GetIncorrectPrimaryStatResult("strengthTrinket", context)
        )
        Harness.AssertFalse(
            inspection:GetIncorrectPrimaryStatResult("mixedTrinket", context)
        )
        Harness.AssertFalse(
            inspection:GetIncorrectPrimaryStatResult("statlessTrinket", context)
        )
        Harness.AssertFalse(
            inspection:GetIncorrectPrimaryStatResult("cachedWithoutStats", context)
        )
        Harness.AssertEqual(
            gearPolice.Constants.ItemMetadataPending,
            inspection:GetIncorrectPrimaryStatResult("missing", context)
        )
        Harness.AssertEqual(
            gearPolice.Constants.ItemMetadataPending,
            inspection:GetIncorrectPrimaryStatResult("strengthTrinket", {
                unitLevel = 90,
            })
        )
        Harness.AssertFalse(inspection:GetIncorrectPrimaryStatResult("strengthTrinket", {
            unitLevel = 9,
        }))
    end)

    Harness.Add(suite, "new rule messages include actual and expected values", function()
        local environment = LoadGearChecks()
        local rules = environment.GearPolice.Rules
        local armorRule = rules.GetRuleDefinition("incorrect_armor_type")
        local primaryStatRule = rules.GetRuleDefinition("incorrect_primary_stat")

        Harness.AssertEqual(
            "Incorrect Armor Type (Leather, Expected Plate)",
            armorRule.buildMessage(nil, nil, {
                actualArmorType = "Leather",
                expectedArmorType = "Plate",
            }, armorRule)
        )
        Harness.AssertEqual(
            "Incorrect Primary Stat (Intellect, Expected Strength)",
            primaryStatRule.buildMessage(nil, nil, {
                actualPrimaryStatLabels = { "Intellect" },
                expectedPrimaryStatLabel = "Strength",
            }, primaryStatRule)
        )
    end)

    Harness.Add(suite, "scan context captures inspected class level and specialization", function()
        local environment = LoadGearChecks()
        local gearPolice = environment.GearPolice
        local unitByGuid = {
            ["Player-1-REMOTE"] = "target",
            ["Player-1-LOCAL"] = "player",
        }

        gearPolice.Units = {
            GetUnitIdOfPlayerGuid = function(playerGuid)
                return unitByGuid[playerGuid]
            end,
        }
        gearPolice.Settings.IsRuleEnabled = function()
            return true
        end
        gearPolice.IsLocalPlayerGuid = function(_, playerGuid)
            return playerGuid == "Player-1-LOCAL"
        end
        environment.UnitExists = function(unitId)
            return unitId == "target" or unitId == "player"
        end
        environment.UnitGUID = function(unitId)
            return unitId == "target" and "Player-1-REMOTE" or "Player-1-LOCAL"
        end
        environment.UnitClass = function()
            return "Paladin", "PALADIN"
        end
        environment.UnitLevel = function()
            return 90
        end
        environment.GetInspectSpecialization = function()
            return 65
        end
        environment.C_SpecializationInfo = {
            GetSpecialization = function()
                return 3
            end,
            GetSpecializationInfo = function()
                return 70
            end,
        }

        Harness.LoadModule(suite, environment, "Inspection/CheckRunner.lua")

        local remoteContext = gearPolice.Inspection:BuildPlayerCheckContext({
            PlayerGuid = "Player-1-REMOTE",
        })
        Harness.AssertEqual(65, remoteContext.specializationId)
        Harness.AssertEqual("Plate", remoteContext.expectedArmorType)
        Harness.AssertEqual(
            gearPolice.GearStandards.PrimaryStat.Intellect,
            remoteContext.expectedPrimaryStat
        )

        local localContext = gearPolice.Inspection:BuildPlayerCheckContext({
            PlayerGuid = "Player-1-LOCAL",
        })
        Harness.AssertEqual(70, localContext.specializationId)
        Harness.AssertEqual(
            gearPolice.GearStandards.PrimaryStat.Strength,
            localContext.expectedPrimaryStat
        )
    end)

    Harness.Add(suite, "missing local specialization API falls back without throwing", function()
        local environment = LoadGearChecks()
        local gearPolice = environment.GearPolice

        gearPolice.Units = {
            GetUnitIdOfPlayerGuid = function()
                return "player"
            end,
        }
        gearPolice.IsLocalPlayerGuid = function()
            return true
        end
        environment.UnitExists = function()
            return true
        end
        environment.UnitGUID = function()
            return "Player-1-LOCAL"
        end
        environment.UnitClass = function()
            return "Warrior", "WARRIOR"
        end
        environment.UnitLevel = function()
            return 90
        end
        environment.C_SpecializationInfo = nil

        Harness.LoadModule(suite, environment, "Inspection/CheckRunner.lua")

        local context = gearPolice.Inspection:BuildPlayerCheckContext({
            PlayerGuid = "Player-1-LOCAL",
        })
        Harness.AssertEqual(nil, context.specializationId)
        Harness.AssertEqual(
            gearPolice.GearStandards.PrimaryStat.Strength,
            context.expectedPrimaryStat
        )
    end)

    Harness.Add(suite, "rule errors fail the unit check instead of losing slot completion", function()
        local reportedError
        local environment = LoadGearChecks()
        local gearPolice = environment.GearPolice
        local inspection = gearPolice.Inspection

        environment.geterrorhandler = function()
            return function(errorMessage)
                reportedError = errorMessage
            end
        end
        environment.InCombatLockdown = function()
            return false
        end
        gearPolice.Slots.GetInventorySlotNames = function()
            return { "HeadSlot" }
        end
        gearPolice.Rules.GetSlotRuleIdsForSlot = function()
            return { "throwing_rule" }
        end
        gearPolice.Rules.GetRuleDefinition = function()
            return {
                evaluate = function()
                    error("intentional rule failure")
                end,
            }
        end
        gearPolice.Settings.IsRuleEnabled = function()
            return true
        end
        gearPolice.Units = {
            GetUnitIdOfPlayerGuid = function()
                return "player"
            end,
        }
        gearPolice.IsLocalPlayerGuid = function()
            return true
        end
        gearPolice.PauseCurrentScanForCombat = function()
            error("scan should not pause")
        end
        inspection.IsCurrentScan = function()
            return true
        end
        inspection.IsStoredItemLink = function()
            return true
        end
        inspection.ResolveInventorySlotWithRetry = function(_, _, slotName, _, onResolved)
            onResolved(slotName, "item:1", 1)
        end

        Harness.LoadModule(suite, environment, "Inspection/CheckRunner.lua")
        inspection.BuildPlayerCheckContext = function()
            return {}
        end

        local completed = false
        local failed = false
        inspection:CheckUnit({
            PlayerGuid = "Player-1-LOCAL",
        }, function()
            completed = true
        end, 4, function()
            failed = true
        end)

        Harness.AssertFalse(completed)
        Harness.AssertTrue(failed)
        Harness.AssertTrue(type(reportedError) == "string")
        Harness.AssertTrue(reportedError:find("intentional rule failure", 1, true) ~= nil)
    end)

    Harness.Add(suite, "slot checks record both gear standard problems", function()
        local environment = LoadGearChecks()
        local gearPolice = environment.GearPolice
        local recordedProblems = {}

        gearPolice.Units = {
            GetUnitIdOfPlayerGuid = function()
                return "raid8"
            end,
        }
        gearPolice.IsLocalPlayerGuid = function()
            return false
        end
        gearPolice.Settings.IsRuleEnabled = function(_, ruleId)
            return ruleId == "incorrect_armor_type" or ruleId == "incorrect_primary_stat"
        end
        gearPolice.Inspection.IsCurrentScan = function()
            return true
        end
        gearPolice.Inspection.IsStoredItemLink = function()
            return true
        end
        gearPolice.Inspection.RecordProblem = function(_, _, slotName, _, ruleId, message)
            table.insert(recordedProblems, {
                slotName = slotName,
                ruleId = ruleId,
                message = message,
            })
        end

        Harness.LoadModule(suite, environment, "Inspection/CheckRunner.lua")

        gearPolice.Inspection:ApplySlotChecks(
            { PlayerGuid = "Player-1-TEST" },
            "HeadSlot",
            "leather",
            1,
            3,
            {
                unitId = "raid15",
                unitLevel = 90,
                expectedArmorType = "Plate",
                expectedPrimaryStat = gearPolice.GearStandards.PrimaryStat.Strength,
            }
        )

        Harness.AssertEqual(2, #recordedProblems)
        Harness.AssertEqual("incorrect_armor_type", recordedProblems[1].ruleId)
        Harness.AssertEqual(
            "Incorrect Armor Type (Leather, Expected Plate)",
            recordedProblems[1].message
        )
        Harness.AssertEqual("incorrect_primary_stat", recordedProblems[2].ruleId)
        Harness.AssertEqual(
            "Incorrect Primary Stat (Agility, Expected Strength)",
            recordedProblems[2].message
        )
    end)

    Harness.Add(suite, "slot checks refresh moved roster unit tokens", function()
        local environment = LoadGearChecks()
        local gearPolice = environment.GearPolice
        local upgradeUnitId

        gearPolice.Units = {
            GetUnitIdOfPlayerGuid = function()
                return "raid8"
            end,
        }
        gearPolice.IsLocalPlayerGuid = function()
            return false
        end
        gearPolice.Settings.IsRuleEnabled = function(_, ruleId)
            return ruleId == "missing_upgrade"
        end
        gearPolice.Inspection.IsCurrentScan = function()
            return true
        end
        gearPolice.Inspection.IsStoredItemLink = function()
            return true
        end
        gearPolice.Inspection.GetMissingUpgradeResult = function(_, _, unitId)
            upgradeUnitId = unitId
            return false
        end

        Harness.LoadModule(suite, environment, "Inspection/CheckRunner.lua")

        gearPolice.Inspection:ApplySlotChecks(
            { PlayerGuid = "Player-1-TEST" },
            "Trinket0Slot",
            "strengthTrinket",
            13,
            3,
            {
                unitId = "raid15",
                unitLevel = 90,
                expectedArmorType = "Plate",
                expectedPrimaryStat = gearPolice.GearStandards.PrimaryStat.Strength,
            }
        )

        Harness.AssertEqual("raid8", upgradeUnitId)
    end)
end
