std = "lua51"

globals = {
    "GearPolice",
}

read_globals = {
    "LibStub",

    -- WoW UI globals
    "_G",
    "CreateFrame",
    "GameTooltip",
    "UIParent",

    -- WoW unit and group APIs
    "CanInspect",
    "ClearInspectPlayer",
    "GetPlayerInfoByGUID",
    "InCombatLockdown",
    "IsInGroup",
    "IsInRaid",
    "NotifyInspect",
    "UnitExists",
    "UnitGUID",
    "UnitIsPlayer",
    "UnitName",

    -- WoW item and inventory APIs
    "GetDetailedItemLevelInfo",
    "GetInventoryItemID",
    "GetInventoryItemLink",
    "GetInventoryItemTexture",
    "GetInventorySlotInfo",
    "GetItemInfo",
    "GetItemStats",

    -- WoW chat/string/time APIs
    "SendChatMessage",
    "strsplit",
    "time",
}

ignore = {
    "212/self",
}
