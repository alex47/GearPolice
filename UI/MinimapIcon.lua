local GearPolice = GearPolice

local MINIMAP_ICON_PATH = "Interface\\AddOns\\GearPolice\\Media\\GearPoliceIcon.tga"

local function EnsureMinimapSettings()
    GearPolice.db.global.MinimapIcon = GearPolice.db.global.MinimapIcon or {}

    if type(GearPolice.db.global.MinimapIcon.hide) ~= "boolean" then
        GearPolice.db.global.MinimapIcon.hide = false
    end

    return GearPolice.db.global.MinimapIcon
end

function GearPolice:InitializeMinimapIcon()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)

    if not LDB or not LibDBIcon then
        return
    end

    if self.minimapLauncher then
        return
    end

    self.minimapLauncher = LDB:NewDataObject("GearPolice", {
        type = "launcher",
        text = "GearPolice",
        icon = MINIMAP_ICON_PATH,
        OnClick = function(_frame, button)
            if button == "LeftButton" then
                GearPolice.UI:ToggleUI()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("GearPolice")
            tooltip:AddLine("Left-click: Toggle window", 1, 1, 1)
        end,
    })

    LibDBIcon:Register("GearPolice", self.minimapLauncher, EnsureMinimapSettings())
end
