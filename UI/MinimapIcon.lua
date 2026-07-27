local GearPolice = GearPolice

local MINIMAP_ICON_PATH = "Interface\\AddOns\\GearPolice\\Media\\GearPoliceIcon.tga"

function GearPolice:InitializeMinimapIcon()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)

    if not LDB or not LibDBIcon then
        return
    end

    if self.minimapLauncher then
        return
    end

    self.minimapLauncher = LDB:NewDataObject(self.AddonName, {
        type = "launcher",
        text = self.AddonName,
        icon = MINIMAP_ICON_PATH,
        OnClick = function(frame, button)
            if button == "LeftButton" then
                GearPolice.UI:ToggleUI()
            elseif button == "RightButton" then
                GearPolice:OpenMinimapDropDown(frame)
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(GearPolice.AddonName)
            tooltip:AddLine("Left-click: Toggle window", 1, 1, 1)
            tooltip:AddLine("Right-click: Open menu", 1, 1, 1)
        end,
    })

    LibDBIcon:Register(self.AddonName, self.minimapLauncher, self.db.global.MinimapIcon)
end
