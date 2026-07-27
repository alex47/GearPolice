return function(Harness, suite)
    local function LoadRoster()
        local currentName = "Unknown object"
        local scheduledCallbacks = {}
        local playerInfoByGuid = {}
        local queueCount = 0
        local uiUpdateCount = 0
        local processCount = 0
        local playerGuid = "Player-1-LATE"
        local currentUnitGuid = playerGuid

        local environment = Harness.MakeEnvironment({
            GearPolice = {},
            UNKNOWNOBJECT = "Unknown object",
            UNKNOWN = "Unknown",
            IsInRaid = function()
                return false
            end,
            IsInGroup = function()
                return true
            end,
            UnitExists = function(unitId)
                return unitId == "party1"
            end,
            UnitGUID = function(unitId)
                return unitId == "party1" and currentUnitGuid or nil
            end,
            UnitFullName = function(unitId)
                if unitId == "party1" then
                    return currentName, "Realm"
                end
            end,
            UnitName = function(unitId)
                if unitId == "party1" then
                    return currentName, "Realm"
                end
            end,
            GetRealmName = function()
                return "Realm"
            end,
            time = function()
                return 1000
            end,
        })

        Harness.LoadModule(suite, environment, "Config/Constants.lua")
        Harness.LoadModule(suite, environment, "Util/Players.lua")
        Harness.LoadModule(suite, environment, "Services/Roster.lua")

        local addon = environment.GearPolice
        addon.pendingRosterNameRetries = {}
        addon.currentRoster = {
            presentGuids = { [playerGuid] = true },
            unitIdByGuid = { [playerGuid] = "party1" },
            sortIndexByGuid = { [playerGuid] = 1 },
            orderedGuids = { playerGuid },
            groupType = "party",
        }
        addon.PlayerStore = {
            Get = function(_, guid)
                return playerInfoByGuid[guid]
            end,
            SetDefault = function(_, guid)
                local info = {
                    PlayerGuid = guid,
                    CheckStatus = addon.Constants.ScanStatus.InProgress,
                    LastScanTime = 0,
                }
                playerInfoByGuid[guid] = info
                return info
            end,
        }
        addon.ScheduleManagedTimer = function(_, callback)
            table.insert(scheduledCallbacks, callback)
            return #scheduledCallbacks
        end
        addon.AddToScanQueue = function()
            queueCount = queueCount + 1
            return true
        end
        addon.HasScheduledPlayerWork = function()
            return false
        end
        addon.UI = {
            UpdateUI = function()
                uiUpdateCount = uiUpdateCount + 1
            end,
        }
        addon.ProcessScanQueue = function()
            processCount = processCount + 1
        end

        return {
            addon = addon,
            environment = environment,
            playerGuid = playerGuid,
            scheduledCallbacks = scheduledCallbacks,
            setName = function(name)
                currentName = name
            end,
            setUnitGuid = function(guid)
                currentUnitGuid = guid
            end,
            getQueueCount = function()
                return queueCount
            end,
            getUiUpdateCount = function()
                return uiUpdateCount
            end,
            getProcessCount = function()
                return processCount
            end,
            getPlayerInfo = function()
                return playerInfoByGuid[playerGuid]
            end,
        }
    end

    Harness.Add(suite, "roster name retries are single-flight and resume scanning", function()
        local test = LoadRoster()
        local roster = test.addon.Roster

        Harness.AssertFalse(roster.ProcessGroupMember(test.addon, "party1", 1, "party"))
        Harness.AssertFalse(roster.ProcessGroupMember(test.addon, "party1", 1, "party"))
        Harness.AssertEqual(1, #test.scheduledCallbacks)

        test.setName("Lateplayer")
        test.scheduledCallbacks[1]()

        local playerInfo = test.getPlayerInfo()
        Harness.AssertEqual("Lateplayer", playerInfo.PlayerName)
        Harness.AssertEqual("Lateplayer-Realm", playerInfo.PlayerFullName)
        Harness.AssertEqual(1, test.getQueueCount())
        Harness.AssertEqual(1, test.getUiUpdateCount())
        Harness.AssertEqual(1, test.getProcessCount())
        Harness.AssertEqual(nil, test.addon.pendingRosterNameRetries[test.playerGuid])
    end)

    Harness.Add(suite, "stale roster retry identities cannot clear newer work", function()
        local test = LoadRoster()
        test.addon.Roster.ProcessGroupMember(test.addon, "party1", 1, "party")

        local newerRecord = {}
        test.addon.pendingRosterNameRetries[test.playerGuid] = newerRecord
        test.scheduledCallbacks[1]()

        Harness.AssertEqual(
            newerRecord,
            test.addon.pendingRosterNameRetries[test.playerGuid]
        )
        Harness.AssertEqual(0, test.getUiUpdateCount())
        Harness.AssertEqual(0, test.getProcessCount())
    end)

    Harness.Add(suite, "removed or remapped roster players ignore delayed name retries", function()
        local removed = LoadRoster()
        removed.addon.Roster.ProcessGroupMember(removed.addon, "party1", 1, "party")
        removed.addon.currentRoster.unitIdByGuid[removed.playerGuid] = nil
        removed.scheduledCallbacks[1]()
        Harness.AssertEqual(nil, removed.getPlayerInfo())
        Harness.AssertEqual(0, removed.getUiUpdateCount())
        Harness.AssertEqual(0, removed.getProcessCount())

        local remapped = LoadRoster()
        remapped.addon.Roster.ProcessGroupMember(remapped.addon, "party1", 1, "party")
        remapped.setUnitGuid("Player-1-OTHER")
        remapped.scheduledCallbacks[1]()
        Harness.AssertEqual(nil, remapped.getPlayerInfo())
        Harness.AssertEqual(0, remapped.getUiUpdateCount())
        Harness.AssertEqual(0, remapped.getProcessCount())
    end)

    local function LoadReportOffers()
        local filters = {}
        local shown = false
        local now = 1000
        local scheduledCallbacks = {}
        local playersByGuid = {
            ["Player-1-A"] = {
                PlayerGuid = "Player-1-A",
                PlayerName = "Same",
                PlayerFullName = "Same-RealmA",
            },
            ["Player-1-B"] = {
                PlayerGuid = "Player-1-B",
                PlayerName = "Same",
                PlayerFullName = "Same-RealmB",
            },
        }
        local environment = Harness.MakeEnvironment({
            GearPolice = {
                Settings = {
                    IsAutoWhispersShown = function()
                        return shown
                    end,
                },
                AutomaticMessageFlow = {
                    Create = function()
                        return {
                            Initialize = function() end,
                            MaybeSend = function() return false end,
                            SchedulePendingCombat = function() return false end,
                            SendPendingCoordination = function() return false end,
                            ClearPending = function() end,
                            ClearAllPending = function() end,
                            Record = function() return true end,
                        }
                    end,
                },
                Reporting = {},
                Units = {},
            },
            ChatFrameUtil = {
                AddMessageEventFilter = function(eventName, filter)
                    filters[eventName] = filter
                end,
            },
            time = function()
                return now
            end,
            GetRealmName = function()
                return "Home Realm"
            end,
        })
        environment.GearPolice.ScheduleTimer = function(_, callback)
            table.insert(scheduledCallbacks, callback)
            return #scheduledCallbacks
        end

        Harness.LoadModule(suite, environment, "Config/Constants.lua")
        Harness.LoadModule(suite, environment, "Util/Players.lua")
        environment.GearPolice.PlayerStore = {
            Get = function(_, guid)
                return playersByGuid[guid]
            end,
            GetAll = function()
                return playersByGuid
            end,
        }
        Harness.LoadModule(suite, environment, "Services/ReportOffers.lua")
        environment.GearPolice.ReportOffers:RegisterChatFilters()

        local function Filter(message, recipient, lineId)
            return filters.CHAT_MSG_WHISPER_INFORM(
                nil,
                "CHAT_MSG_WHISPER_INFORM",
                message,
                recipient,
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                lineId
            )
        end

        return {
            gearPolice = environment.GearPolice,
            filter = Filter,
            setShown = function(value)
                shown = value
            end,
            setNow = function(value)
                now = value
            end,
            scheduledCallbacks = scheduledCallbacks,
        }
    end

    Harness.Add(suite, "outgoing suppression is idempotent across chat frames", function()
        local test = LoadReportOffers()
        local addon = test.gearPolice

        addon:RegisterReportOfferOutgoingWhisper("Target-Realm", "Automated line")
        Harness.AssertTrue(test.filter("Automated line", "Target-Realm", 100))
        Harness.AssertTrue(test.filter("Automated line", "Target-Realm", 100))
        Harness.AssertFalse(test.filter("Automated line", "Target-Realm", 101))
        Harness.AssertFalse(test.filter("Automated line", "Other-Realm", 102))

        addon:RegisterReportOfferOutgoingWhisper(
            "Localtarget-Home Realm",
            "Same realm"
        )
        Harness.AssertTrue(test.filter("Same realm", "Localtarget", 103))
    end)

    Harness.Add(suite, "suppression counts duplicates and applies the delivery-time toggle", function()
        local test = LoadReportOffers()
        local addon = test.gearPolice

        addon:RegisterReportOfferOutgoingWhisper("Target-Realm", "Duplicate")
        addon:RegisterReportOfferOutgoingWhisper("Target-Realm", "Duplicate")
        Harness.AssertTrue(test.filter("Duplicate", "Target-Realm", 200))
        Harness.AssertTrue(test.filter("Duplicate", "Target-Realm", 201))
        Harness.AssertFalse(test.filter("Duplicate", "Target-Realm", 202))

        addon:RegisterReportOfferOutgoingWhisper("Target-Realm", "Toggle")
        test.setShown(true)
        Harness.AssertFalse(test.filter("Toggle", "Target-Realm", 203))
        test.setShown(false)
        Harness.AssertFalse(test.filter("Toggle", "Target-Realm", 204))
        Harness.AssertFalse(test.filter("Manual", "Target-Realm", 205))
    end)

    Harness.Add(suite, "suppression expires stale entries and supports missing line IDs", function()
        local test = LoadReportOffers()
        local addon = test.gearPolice

        addon:RegisterReportOfferOutgoingWhisper("Target-Realm", "Old")
        test.setNow(1300)
        Harness.AssertFalse(test.filter("Old", "Target-Realm", 300))

        addon:RegisterReportOfferOutgoingWhisper("Target-Realm", "Fallback")
        Harness.AssertTrue(test.filter("Fallback", "Target-Realm", nil))
        Harness.AssertTrue(test.filter("Fallback", "Target-Realm", nil))
        Harness.AssertEqual(1, #test.scheduledCallbacks)
        test.scheduledCallbacks[1]()
        Harness.AssertFalse(test.filter("Fallback", "Target-Realm", nil))
    end)

    Harness.Add(suite, "duplicate short names require an exact full-name match", function()
        local test = LoadReportOffers()
        local offers = test.gearPolice.ReportOffers

        Harness.AssertEqual(nil, offers:FindPlayerInfo(nil, "Same"))
        Harness.AssertEqual(
            "Player-1-A",
            offers:FindPlayerInfo(nil, "Same-RealmA").PlayerGuid
        )
    end)
end
