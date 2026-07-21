local GearPolice = GearPolice

GearPolice.Constants = GearPolice.Constants or {}

local Constants = GearPolice.Constants

Constants.InventorySlotReady = "READY"
Constants.InventorySlotPending = "PENDING"
Constants.InventorySlotNoEvidence = "NO_EVIDENCE"
Constants.InventorySlotEmpty = "EMPTY"
Constants.ItemMetadataPending = "PENDING_METADATA"

Constants.ScanInterval = 2
Constants.ScanQueueAvailabilityInterval = 5
Constants.InspectReadyTimeout = 8

Constants.InventorySlotRetryCount = 6
Constants.InventorySlotRetryDelay = 2
Constants.InventorySlotEmptyConfirmations = 5
Constants.InventorySnapshotEvidenceMinimum = 4

Constants.ItemLevelThreshold = 450

-- Compatibility aliases. Later refactor phases can move callers to GearPolice.Constants.
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
