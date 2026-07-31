return function(Harness, suite)
    Harness.Add(suite, "automatic group scan setting defaults on and runs toggle actions", function()
        local queuedFreshScans = 0
        local cancelledScans = 0
        local environment = Harness.MakeEnvironment({
            GearPolice = {
                db = {
                    global = {},
                },
                QueueFreshGroupScan = function()
                    queuedFreshScans = queuedFreshScans + 1
                end,
                CancelAutomaticGroupScans = function()
                    cancelledScans = cancelledScans + 1
                end,
            },
            IsInGroup = function()
                return true
            end,
            IsInRaid = function()
                return false
            end,
        })

        Harness.LoadModule(suite, environment, "Config/Constants.lua")
        Harness.LoadModule(suite, environment, "Services/Settings.lua")

        local settings = environment.GearPolice.Settings
        Harness.AssertTrue(settings:IsAutomaticGroupScanEnabled())
        Harness.AssertTrue(settings:SetAutomaticGroupScanEnabled(false))
        Harness.AssertFalse(settings:IsAutomaticGroupScanEnabled())
        Harness.AssertEqual(1, cancelledScans)
        Harness.AssertEqual(0, queuedFreshScans)

        Harness.AssertTrue(settings:SetAutomaticGroupScanEnabled(true))
        Harness.AssertTrue(settings:IsAutomaticGroupScanEnabled())
        Harness.AssertEqual(1, cancelledScans)
        Harness.AssertEqual(1, queuedFreshScans)

        Harness.AssertTrue(settings:SetAutomaticGroupScanEnabled(true))
        Harness.AssertEqual(1, queuedFreshScans)
    end)

    local function LoadRoster(autoScanEnabled)
        local playerGuid = "Player-1-MEMBER"
        local playerInfoByGuid = {}
        local queuedCount = 0
        local environment = Harness.MakeEnvironment({
            GearPolice = {},
            IsInGroup = function()
                return true
            end,
            IsInRaid = function()
                return false
            end,
            UnitExists = function(unitId)
                return unitId == "party1"
            end,
            UnitGUID = function(unitId)
                return unitId == "party1" and playerGuid or nil
            end,
            UnitName = function(unitId)
                if unitId == "party1" then
                    return "Member", "Realm"
                end
            end,
            UnitFullName = function(unitId)
                if unitId == "party1" then
                    return "Member", "Realm"
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
        addon.Settings = {
            IsAutomaticGroupScanEnabled = function()
                return autoScanEnabled
            end,
        }
        addon.PlayerStore = {
            Get = function(_, guid)
                return playerInfoByGuid[guid]
            end,
            SetDefault = function(_, guid)
                local playerInfo = {
                    PlayerGuid = guid,
                    CheckStatus = addon.Constants.ScanStatus.InProgress,
                    LastScanTime = 0,
                    ScanGeneration = 0,
                }
                playerInfoByGuid[guid] = playerInfo
                return playerInfo
            end,
            MarkNotScanned = function(_, playerInfo)
                playerInfo.CheckStatus = addon.Constants.ScanStatus.NotScanned
                playerInfo.CheckRequested = false
                return true
            end,
        }
        addon.AddToScanQueue = function()
            queuedCount = queuedCount + 1
            return true
        end
        addon.HasScheduledPlayerWork = function()
            return false
        end
        addon.ResetPlayerGearInfo = function(_, guid, playerName, playerFullName)
            playerInfoByGuid[guid] = {
                PlayerGuid = guid,
                PlayerName = playerName,
                PlayerFullName = playerFullName,
                CheckStatus = addon.Constants.ScanStatus.InProgress,
                LastScanTime = 0,
                ScanGeneration = 1,
            }
        end

        return addon, playerInfoByGuid, function()
            return queuedCount
        end
    end

    Harness.Add(suite, "disabled auto-scan tracks roster members without queueing them", function()
        local addon, playerInfoByGuid, getQueuedCount = LoadRoster(false)
        local processed = addon.Roster.ProcessGroupMember(
            addon,
            "party1",
            1,
            "party"
        )

        Harness.AssertTrue(processed)
        Harness.AssertEqual(0, getQueuedCount())
        Harness.AssertEqual(
            addon.Constants.ScanStatus.NotScanned,
            playerInfoByGuid["Player-1-MEMBER"].CheckStatus
        )
    end)

    Harness.Add(suite, "fresh manual group scans override disabled auto-scan", function()
        local addon, playerInfoByGuid, getQueuedCount = LoadRoster(false)
        local processed = addon.Roster.ProcessGroupMember(
            addon,
            "party1",
            1,
            "party",
            {
                queueGroupScans = true,
                forceFreshScans = true,
            }
        )

        Harness.AssertTrue(processed)
        Harness.AssertEqual(1, getQueuedCount())
        Harness.AssertEqual(
            addon.Constants.ScanStatus.InProgress,
            playerInfoByGuid["Player-1-MEMBER"].CheckStatus
        )
    end)

    Harness.Add(suite, "disabling auto-scan cancels only group-owned scan work", function()
        local groupGuid = "Player-1-GROUP"
        local targetGuid = "Player-1-TARGET"
        local processedQueueCount = 0
        local playerInfo = {
            PlayerGuid = groupGuid,
            CheckStatus = "InProgress",
        }
        local environment = Harness.MakeEnvironment({
            GearPolice = {},
            InCombatLockdown = function()
                return false
            end,
        })

        Harness.LoadModule(suite, environment, "Config/Constants.lua")
        Harness.LoadModule(suite, environment, "Services/ScanSession.lua")

        local addon = environment.GearPolice
        playerInfo.CheckStatus = addon.Constants.ScanStatus.InProgress
        addon.currentScan = {
            playerGuid = groupGuid,
            reason = addon.Constants.ScanReason.Group,
        }
        addon.scanQueue = { groupGuid, targetGuid }
        addon.queuedScanReasons = {
            [groupGuid] = addon.Constants.ScanReason.Group,
            [targetGuid] = addon.Constants.ScanReason.Target,
        }
        addon.delayedScanRetries = {
            [groupGuid] = {
                reason = addon.Constants.ScanReason.Group,
            },
        }
        addon.pendingRosterNameRetries = {
            [groupGuid] = {
                queueGroupScans = true,
                forceFreshScans = true,
            },
        }
        addon.PlayerStore = {
            Get = function(_, guid)
                return guid == groupGuid and playerInfo or nil
            end,
            MarkNotScanned = function(_, info)
                info.CheckStatus = addon.Constants.ScanStatus.NotScanned
            end,
        }
        addon.CancelManagedTimersForPlayer = function() end
        addon.RemoveFromScanQueue = function(_, guid)
            for index = #addon.scanQueue, 1, -1 do
                if addon.scanQueue[index] == guid then
                    table.remove(addon.scanQueue, index)
                end
            end
            addon.queuedScanReasons[guid] = nil
        end
        addon.ClearPendingReportOffer = function() end
        addon.ClearPendingPublicScanAnnouncement = function() end
        addon.CancelScanQueueTimer = function() end
        addon.ProcessScanQueue = function()
            processedQueueCount = processedQueueCount + 1
        end
        addon.UI = {
            UpdateUI = function() end,
        }

        Harness.AssertTrue(addon.ScanSession.CancelAutomaticGroupScans(addon))
        Harness.AssertEqual(nil, addon.currentScan)
        Harness.AssertEqual(1, #addon.scanQueue)
        Harness.AssertEqual(targetGuid, addon.scanQueue[1])
        Harness.AssertEqual(
            addon.Constants.ScanReason.Target,
            addon.queuedScanReasons[targetGuid]
        )
        Harness.AssertEqual(nil, addon.delayedScanRetries[groupGuid])
        Harness.AssertEqual(nil, addon.pendingRosterNameRetries[groupGuid])
        Harness.AssertEqual(addon.Constants.ScanStatus.NotScanned, playerInfo.CheckStatus)
        Harness.AssertEqual(1, processedQueueCount)
    end)

    Harness.Add(suite, "disabling auto-scan preserves completed scan results", function()
        local playerGuid = "Player-1-COMPLETE"
        local playerInfo = {
            PlayerGuid = playerGuid,
            CheckStatus = "Successful",
            CheckRequested = true,
            ForceScanRequested = true,
            ScanGeneration = 4,
            Problems = { { message = "Missing Gem" } },
        }
        local environment = Harness.MakeEnvironment({
            GearPolice = {},
            InCombatLockdown = function()
                return false
            end,
        })

        Harness.LoadModule(suite, environment, "Config/Constants.lua")
        Harness.LoadModule(suite, environment, "Services/ScanSession.lua")

        local addon = environment.GearPolice
        playerInfo.CheckStatus = addon.Constants.ScanStatus.Successful
        addon.scanQueue = { playerGuid }
        addon.queuedScanReasons = {
            [playerGuid] = addon.Constants.ScanReason.Group,
        }
        addon.PlayerStore = {
            Get = function()
                return playerInfo
            end,
            MarkNotScanned = function()
                error("completed scans must not be cleared")
            end,
        }
        addon.CancelManagedTimersForPlayer = function() end
        addon.RemoveFromScanQueue = function(_, guid)
            if guid == playerGuid then
                addon.scanQueue = {}
                addon.queuedScanReasons[guid] = nil
            end
        end
        addon.ClearCurrentScanForPlayer = function() end
        addon.CancelScanQueueTimer = function() end
        addon.ProcessScanQueue = function() end
        addon.UI = {
            UpdateUI = function() end,
        }

        Harness.AssertTrue(addon.ScanSession.CancelAutomaticGroupScans(addon))
        Harness.AssertEqual(addon.Constants.ScanStatus.Successful, playerInfo.CheckStatus)
        Harness.AssertEqual("Missing Gem", playerInfo.Problems[1].message)
        Harness.AssertFalse(playerInfo.CheckRequested)
        Harness.AssertFalse(playerInfo.ForceScanRequested)
        Harness.AssertEqual(5, playerInfo.ScanGeneration)
    end)
end
