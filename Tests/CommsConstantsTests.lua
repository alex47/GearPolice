return function(Harness, suite)
    local function StrSplit(delimiter, value)
        local fields = {}
        local startIndex = 1

        while true do
            local delimiterIndex = string.find(value, delimiter, startIndex, true)
            if not delimiterIndex then
                table.insert(fields, string.sub(value, startIndex))
                break
            end

            table.insert(fields, string.sub(value, startIndex, delimiterIndex - 1))
            startIndex = delimiterIndex + #delimiter
        end

        return unpack(fields)
    end

    local function LoadComms()
        local now = 1000
        local units = {
            player = {
                guid = "Player-1-LOCAL",
                name = "Local",
                realm = "Realm",
            },
            party1 = {
                guid = "Player-1-LEADER",
                name = "Leader",
                realm = "Realm",
            },
            party2 = {
                guid = "Player-1-TARGET",
                name = "Target",
                realm = "Realm",
            },
        }
        local guidToUnit = {}
        for unitId, unit in pairs(units) do
            guidToUnit[unit.guid] = unitId
        end

        local environment = Harness.MakeEnvironment({
            GearPolice = {
                AddonName = "GearPolice",
                Settings = {
                    IsReportOfferEnabled = function()
                        return false
                    end,
                    IsAutoWhisperEnabledForCurrentGroup = function()
                        return false
                    end,
                    IsPublicScanAnnouncementEnabledForCurrentGroup = function()
                        return false
                    end,
                },
                Debug = {
                    Message = function() end,
                },
            },
            IsInRaid = function()
                return false
            end,
            IsInGroup = function()
                return true
            end,
            UnitGUID = function(unitId)
                local unit = units[unitId]
                return unit and unit.guid or nil
            end,
            UnitExists = function(unitId)
                return units[unitId] ~= nil
            end,
            UnitName = function(unitId)
                local unit = units[unitId]
                return unit and unit.name or nil, unit and unit.realm or nil
            end,
            UnitFullName = function(unitId)
                local unit = units[unitId]
                return unit and unit.name or nil, unit and unit.realm or nil
            end,
            UnitIsGroupLeader = function(unitId)
                return unitId == "party1"
            end,
            UnitIsGroupAssistant = function()
                return false
            end,
            GetRealmName = function()
                return "Realm"
            end,
            GetAddOnMetadata = function()
                return "1.5.1"
            end,
            strsplit = StrSplit,
            time = function()
                return now
            end,
        })

        Harness.LoadModule(suite, environment, "Config/Constants.lua")
        Harness.LoadModule(suite, environment, "Util/Players.lua")
        Harness.LoadModule(suite, environment, "Services/AutomaticMessageFlow.lua")

        local addon = environment.GearPolice
        addon.Units = {
            GetGroupChatType = function()
                return "PARTY"
            end,
            GetUnitIdOfPlayerGuid = function(guid)
                return guidToUnit[guid]
            end,
            IsPlayerInGroup = function(guid)
                return guidToUnit[guid] ~= nil
            end,
        }
        addon.PlayerStore = {
            Get = function()
                return nil
            end,
        }
        addon.currentRoster = {
            presentGuids = {
                ["Player-1-LOCAL"] = true,
                ["Player-1-LEADER"] = true,
                ["Player-1-TARGET"] = true,
            },
            unitIdByGuid = {
                ["Player-1-LOCAL"] = "player",
                ["Player-1-LEADER"] = "party1",
                ["Player-1-TARGET"] = "party2",
            },
            sortIndexByGuid = {
                ["Player-1-LOCAL"] = 0,
                ["Player-1-LEADER"] = 1,
                ["Player-1-TARGET"] = 2,
            },
            orderedGuids = {
                "Player-1-LOCAL",
                "Player-1-LEADER",
                "Player-1-TARGET",
            },
            groupType = "party",
        }
        addon.BuildGroupRosterSnapshot = function()
            return addon.currentRoster
        end

        local reportOfferFlow = addon.AutomaticMessageFlow.Create({
            historyKey = "ReportOfferHistory",
            timestampField = "lastOfferedAt",
            isEligible = function()
                return true
            end,
            send = function()
                return true
            end,
        })
        addon.db = {
            global = {},
        }
        addon.RecordReportOffer = function(_, playerGuid)
            return reportOfferFlow:Record(playerGuid)
        end

        local publicRecordCount = 0
        addon.RecordPublicScanAnnouncement = function()
            publicRecordCount = publicRecordCount + 1
        end
        addon.RegisterComm = function() end

        Harness.LoadModule(suite, environment, "Services/Comms.lua")
        addon:InitializeComms()

        return {
            addon = addon,
            reportOfferFlow = reportOfferFlow,
            getPublicRecordCount = function()
                return publicRecordCount
            end,
        }
    end

    Harness.Add(suite, "authenticated coordinator messages synchronize both cooldowns", function()
        local test = LoadComms()
        local addon = test.addon
        addon:OnGearPoliceCommReceived(
            "GearPolice",
            "STATE\t1\t1.5.1\tPlayer-1-LEADER\t1\tLeader-Realm\t1",
            "PARTY",
            "Leader-Realm"
        )

        addon:OnGearPoliceCommReceived(
            "GearPolice",
            "REPORT_OFFERED\t1\tPlayer-1-LEADER\tPlayer-1-TARGET",
            "PARTY",
            "Leader-Realm"
        )
        Harness.AssertTrue(test.reportOfferFlow:IsOnCooldown("Player-1-TARGET"))

        addon:OnGearPoliceCommReceived(
            "GearPolice",
            "PUBLIC_ANNOUNCED\t1\tPlayer-1-LEADER\tPlayer-1-TARGET",
            "PARTY",
            "Leader-Realm"
        )
        Harness.AssertEqual(1, test.getPublicRecordCount())
    end)

    Harness.Add(suite, "mismatched and non-coordinator cooldown messages are rejected", function()
        local test = LoadComms()
        local addon = test.addon
        addon:OnGearPoliceCommReceived(
            "GearPolice",
            "STATE\t1\t1.5.1\tPlayer-1-LEADER\t1\tLeader-Realm\t0",
            "PARTY",
            "Leader-Realm"
        )
        addon:OnGearPoliceCommReceived(
            "GearPolice",
            "STATE\t1\t1.5.1\tPlayer-1-TARGET\t1\tTarget-Realm\t0",
            "PARTY",
            "Target-Realm"
        )

        addon:OnGearPoliceCommReceived(
            "GearPolice",
            "REPORT_OFFERED\t1\tPlayer-1-TARGET\tPlayer-1-LOCAL",
            "PARTY",
            "Target-Realm"
        )
        Harness.AssertFalse(test.reportOfferFlow:IsOnCooldown("Player-1-LOCAL"))

        addon:OnGearPoliceCommReceived(
            "GearPolice",
            "REPORT_OFFERED\t1\tPlayer-1-TARGET\tPlayer-1-LOCAL",
            "PARTY",
            "Leader-Realm"
        )
        Harness.AssertFalse(test.reportOfferFlow:IsOnCooldown("Player-1-LOCAL"))

        local ineligible = LoadComms()
        ineligible.addon:OnGearPoliceCommReceived(
            "GearPolice",
            "STATE\t1\t1.5.1\tPlayer-1-LEADER\t0\tLeader-Realm\t0",
            "PARTY",
            "Leader-Realm"
        )
        ineligible.addon:OnGearPoliceCommReceived(
            "GearPolice",
            "REPORT_OFFERED\t1\tPlayer-1-LEADER\tPlayer-1-TARGET",
            "PARTY",
            "Leader-Realm"
        )
        Harness.AssertFalse(
            ineligible.reportOfferFlow:IsOnCooldown("Player-1-TARGET")
        )
    end)

    Harness.Add(suite, "canonical constants preserve retry policy", function()
        local environment = Harness.MakeEnvironment({
            GearPolice = {},
        })
        Harness.LoadModule(suite, environment, "Config/Constants.lua")
        local constants = environment.GearPolice.Constants

        Harness.AssertEqual(1, constants.PlayerNameRetryDelay)
        Harness.AssertEqual(5, constants.InspectRetryMaxAttempts)
        Harness.AssertEqual(60, constants.PartialScanRetryDelay)
        Harness.AssertEqual(300, constants.TemporaryFailedScanRetryDelay)
        Harness.AssertEqual(24 * 60 * 60, constants.StaleScanAgeSeconds)
        Harness.AssertEqual(300, constants.OutgoingWhisperSuppressionExpirySeconds)
        Harness.AssertEqual(30, constants.ProcessedChatLineCacheLifetimeSeconds)
    end)

    Harness.Add(suite, "production modules do not read compatibility constants", function()
        local productionFiles = {
            "Core.lua",
            "Inspection.lua",
            "Inspection/CheckRunner.lua",
            "Inspection/ItemChecks.lua",
            "Inspection/SlotResolver.lua",
            "Services/Roster.lua",
            "Services/ScanQueue.lua",
            "Services/ScanSession.lua",
            "State/PlayerStore.lua",
            "UI/ViewModel.lua",
            "Util/Inventory.lua",
        }
        local forbiddenReads = {
            "GearPolice.InventorySlotReady",
            "GearPolice.InventorySlotPending",
            "GearPolice.InventorySlotNoEvidence",
            "GearPolice.InventorySlotEmpty",
            "GearPolice.ItemMetadataPending",
            "addon.scanInterval",
            "addon.scanQueueAvailabilityInterval",
            "addon.inspectReadyTimeout",
        }

        for _, relativePath in ipairs(productionFiles) do
            local file = assert(io.open(suite.projectRoot .. "/" .. relativePath, "r"))
            local source = file:read("*a")
            file:close()

            for _, forbiddenRead in ipairs(forbiddenReads) do
                Harness.AssertFalse(
                    string.find(source, forbiddenRead, 1, true),
                    relativePath .. " still reads " .. forbiddenRead
                )
            end
        end
    end)
end
