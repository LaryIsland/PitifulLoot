local addonName, ns = ...

-- A button on the edge of the minimap, since Forever keeps its addons menu hidden: left-click for the window,
-- right-click for its options, and drag it round the edge to move it. It's made by LibDBIcon, the library most addons
-- use for theirs, so it looks like them and minimap button collectors know it. The Minimap Button option hides it;
-- LibDBIcon keeps its place in the settings (minimapIcon).

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
		GameTooltip_AddInstructionLine(tooltip, "Left-click to show or hide the window.")
		GameTooltip_AddInstructionLine(tooltip, "Right-click for options.")
		GameTooltip_AddInstructionLine(tooltip, "Drag to move.")
	end,
})

local icon = LibStub("LibDBIcon-1.0")

local function Update()
	local saved = ns.settings.minimapIcon
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
	if key == "minimapButton" then Update() end
end)

-- For tests and the probe.
function ns.MinimapButton()
	return icon:GetMinimapButton(addonName)
end
