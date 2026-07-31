local GearPolice = GearPolice

GearPolice.Constants = GearPolice.Constants or {}

local Constants = GearPolice.Constants

Constants.ScanStatus = {
    NotScanned = "NotScanned",
    InProgress = "InProgress",
    Successful = "Successful",
    Partial = "Partial",
    Failed = "Failed",
    TemporaryFailed = "TemporaryFailed",
    Cancelled = "Cancelled",
}

Constants.ScanReason = {
    Group = "group",
    Target = "target",
}

Constants.InventorySlotReady = "READY"
Constants.InventorySlotPending = "PENDING"
Constants.InventorySlotNoEvidence = "NO_EVIDENCE"
Constants.InventorySlotEmpty = "EMPTY"
Constants.ItemMetadataPending = "PENDING_METADATA"

Constants.ScanInterval = 2
Constants.ScanQueueAvailabilityInterval = 5
Constants.InspectReadyTimeout = 8
Constants.PlayerNameRetryDelay = 1
Constants.InspectRetryMaxAttempts = 5
Constants.PartialScanRetryDelay = 60
Constants.TemporaryFailedScanRetryDelay = 300
Constants.StaleScanAgeSeconds = 24 * 60 * 60
Constants.AutomaticPlayerMessageCooldownSeconds = 12 * 60 * 60
Constants.AutomaticMessageCombatDelaySeconds = 5
Constants.OutgoingWhisperSuppressionExpirySeconds = 5 * 60
Constants.ProcessedChatLineCacheLifetimeSeconds = 30

Constants.InventorySlotRetryCount = 6
Constants.InventorySlotRetryDelay = 2
Constants.InventorySlotEmptyConfirmations = 5
Constants.InventorySnapshotEvidenceMinimum = 4

Constants.ItemLevelThreshold = 450

-- Compatibility aliases for legacy and external callers.
GearPolice.InventorySlotReady = Constants.InventorySlotReady
GearPolice.InventorySlotPending = Constants.InventorySlotPending
GearPolice.InventorySlotNoEvidence = Constants.InventorySlotNoEvidence
GearPolice.InventorySlotEmpty = Constants.InventorySlotEmpty
GearPolice.ItemMetadataPending = Constants.ItemMetadataPending

GearPolice.scanInterval = Constants.ScanInterval
GearPolice.scanQueueAvailabilityInterval = Constants.ScanQueueAvailabilityInterval
GearPolice.inspectReadyTimeout = Constants.InspectReadyTimeout

GearPolice.InventorySlotRetryCount = Constants.InventorySlotRetryCount
GearPolice.InventorySlotRetryDelay = Constants.InventorySlotRetryDelay
GearPolice.InventorySlotEmptyConfirmations = Constants.InventorySlotEmptyConfirmations
GearPolice.InventorySnapshotEvidenceMinimum = Constants.InventorySnapshotEvidenceMinimum
GearPolice.ItemLevelThreshold = Constants.ItemLevelThreshold
