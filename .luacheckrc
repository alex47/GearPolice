std = "lua51"

globals = {
    "GearPolice",
}

read_globals = {
    "LibStub",

    -- WoW UI globals
    "_G",
    "CreateFrame",
    "AddonCompartmentFrame",
    "CloseDropDownMenus",
    "DropDownList1",
    "GameTooltip",
    "UIParent",
    "ToggleDropDownMenu",
    "UIDROPDOWNMENU_MENU_VALUE",
    "UIDropDownMenu_AddButton",
    "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_SetDisplayMode",
    "UIDropDownMenu_SetInitializeFunction",

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
    "ChatFrame_AddMessageEventFilter",
    "ChatFrameUtil",
    "ChatThrottleLib",
    "SendChatMessage",
    "strsplit",
    "time",
}

ignore = {
    "212/self",
}
