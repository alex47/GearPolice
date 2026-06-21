local GearPolice = GearPolice

GearPolice.Slots = GearPolice.Slots or {}

local Slots = GearPolice.Slots

local InventorySlotNames = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
    "Finger0Slot", "Finger1Slot", "MainHandSlot", "SecondaryHandSlot",
    "Trinket0Slot", "Trinket1Slot"
}

local InventorySnapshotEvidenceSlotNames = {
    "HeadSlot", "ShoulderSlot", "ChestSlot", "HandsSlot", "WaistSlot",
    "LegsSlot", "FeetSlot", "MainHandSlot"
}

function Slots.GetInventorySlotNames()
    return InventorySlotNames
end

function Slots.GetInventorySnapshotEvidenceSlotNames()
    return InventorySnapshotEvidenceSlotNames
end
