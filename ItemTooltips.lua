local _, ns = ...
local L = ns.L

-- Your pity on an item, or that you've won it, on the game's own item tooltips: bags, chat links, the dungeon journal,
-- other addons' loot lists. It changes the game's tooltips, so it's off until the player turns it on (design document
-- 1.1, the Pity in Item Tooltips option). The window's own item tooltips are left alone, as their rows already say it,
-- and so are the comparison tooltips beside them, which are for the item you're wearing, and items in your bags, bank
-- or equipment.

-- The game's calls that show an item you have (bags and the bank, which includes the bank's own slots, and what you or
-- someone you inspect is wearing), which say nothing.
local HELD = { GetBagItem = true, GetInventoryItem = true }

-- Whether the tooltip is for an item you have, from the call the game filled it with.
local function Held(tooltip)
	local info = tooltip.GetProcessingTooltipInfo and tooltip:GetProcessingTooltipInfo()
		or tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
	return info ~= nil and HELD[info.getterName] == true
end

-- Whether a frame is the window or inside it.
local function InWindow(owner)
	local window = ns.Window and ns.Window()
	while owner and window do
		if owner == window then return true end
		owner = owner.GetParent and owner:GetParent()
	end
	return false
end

local function AddPity(tooltip, data)
	if not ns.settings or not ns.settings.itemTooltipPity or not data then return end
	local item = data.id
	if not canaccessvalue(item) or type(item) ~= "number" then return end
	local owner = tooltip.GetOwner and tooltip:GetOwner()
	-- A comparison tooltip is owned by the tooltip it's beside.
	if owner and owner.GetObjectType and owner:GetObjectType() == "GameTooltip" then return end
	if InWindow(owner) then return end
	local me = UnitGUID("player")
	if Held(tooltip) then return end
	if ns.HasWon(me, item) then
		GameTooltip_AddNormalLine(tooltip, L.ITEM_TOOLTIP_WON)
	else
		local pity = ns.PityOf(me, item)
		if pity > 0 then
			GameTooltip_AddNormalLine(tooltip, L.ITEM_TOOLTIP_PITY:format(HIGHLIGHT_FONT_COLOR_CODE .. "+" .. pity .. FONT_COLOR_CODE_CLOSE))
		end
	end
end

if TooltipDataProcessor and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddPity)
end

-- For tests.
ns.AddItemTooltipPity = AddPity
