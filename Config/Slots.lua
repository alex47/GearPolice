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

local SlotLabels = {
    HeadSlot = "Head",
    NeckSlot = "Neck",
    ShoulderSlot = "Shoulder",
    BackSlot = "Back",
    ChestSlot = "Chest",
    WristSlot = "Wrist",
    HandsSlot = "Hands",
    WaistSlot = "Waist",
    LegsSlot = "Legs",
    FeetSlot = "Feet",
    Finger0Slot = "Finger 1",
    Finger1Slot = "Finger 2",
    MainHandSlot = "Main Hand",
    SecondaryHandSlot = "Off Hand",
    Trinket0Slot = "Trinket 1",
    Trinket1Slot = "Trinket 2",
}

function Slots.GetInventorySlotNames()
    return InventorySlotNames
end

function Slots.GetInventorySnapshotEvidenceSlotNames()
    return InventorySnapshotEvidenceSlotNames
end

function Slots.GetSlotLabel(slotName)
    if not slotName then
        return nil
    end

    return SlotLabels[slotName] or slotName
end
