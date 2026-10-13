local addonName, ns = ...

-- A button on the edge of the minimap, since Forever keeps its addons menu hidden: left-click for the window,
-- right-click for its options, and drag it round the edge to move it. It's made by LibDBIcon, the library most addons
-- use for theirs, so it looks like them and minimap button collectors know it. The Minimap Button option (in the
-- profile) hides it; LibDBIcon keeps its place, the same for every character (minimapIcon).

local launcher = LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
	type = "launcher",
	label = "Pitiful Loot",
	icon = "Interface\\Icons\\INV_Misc_Dice_02",
	OnClick = function(_, mouseButton)
		if mouseButton == "RightButton" then
			ns.OpenOptions()
		else
			ns.ToggleWindow()
		end
	end,
	OnTooltipShow = function(tooltip)
		GameTooltip_SetTitle(tooltip, "Pitiful Loot")
		ns.AddHint(tooltip, ns.L.HINT_MINIMAP_LEFT)
		ns.AddHint(tooltip, ns.L.HINT_MINIMAP_RIGHT)
		ns.AddHint(tooltip, ns.L.HINT_MINIMAP_DRAG)
	end,
})

local icon = LibStub("LibDBIcon-1.0")

local function Update()
	local saved = ns.saved.minimapIcon
	saved.hide = not ns.settings.minimapButton
	if icon:IsRegistered(addonName) then
		icon:Refresh(addonName, saved)
	else
		icon:Register(addonName, launcher, saved)
	end
end

ns.On("ADDON_LOADED", function(name)
	if name == addonName then Update() end
end)
ns.Listen("SETTINGS_CHANGED", function(key)
	if key == nil or key == "minimapButton" then Update() end
end)

-- For tests and the probe.
function ns.MinimapButton()
	return icon:GetMinimapButton(addonName)
end
