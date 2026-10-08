local _, ns = ...

-- The master looter's loot window: which items are worth rolling for, and handing them to the winners (5.1).

local MAX_CANDIDATES = 40

ns.loot = {}
local given = {}

local function Scan()
	local items, byItem = {}, {}
	if ns.IsOfficer(ns.PlayerName()) then
		for slot = 1, GetNumLootItems() do
			local link = LootSlotHasItem(slot) and GetLootSlotLink(slot)
			local item = link and ns.ItemID(link)
			local quality = select(5, GetLootSlotInfo(slot))
			if item and quality and quality >= ns.settings.minQuality then
				if not byItem[item] then
					byItem[item] = { item = item, link = link, copies = 0, boe = ns.IsBoE(item) }
					items[#items + 1] = byItem[item]
				end
				byItem[item].copies = byItem[item].copies + 1
			end
		end
	end
	ns.loot = items
	ns.Fire("LOOT_CHANGED")
end

ns.On("LOOT_OPENED", function()
	given = {}
	Scan()
end)
ns.On("LOOT_SLOT_CLEARED", Scan)
ns.On("LOOT_CLOSED", function()
	given = {}
	ns.loot = {}
	ns.Fire("LOOT_CHANGED")
end)

local function GiveTo(item, name)
	for slot = 1, GetNumLootItems() do
		if not given[slot] and LootSlotHasItem(slot) and ns.ItemID(GetLootSlotLink(slot)) == item then
			for i = 1, MAX_CANDIDATES do
				if ns.SameName(GetMasterLootCandidate(slot, i), name) then
					GiveMasterLoot(slot, i)
					given[slot] = true -- the slot clears later, so don't hand it out twice meanwhile
					return true
				end
			end
		end
	end
	return false
end

-- Gives each winner a copy when this client is the master looter with the loot open; otherwise says who gets it.
function ns.GiveLoot(item, winners)
	local missed = {}
	for _, id in ipairs(winners) do
		local name = ns.NameOf(id)
		if not (IsMasterLooter() and GiveTo(item, name)) then missed[#missed + 1] = name end
	end
	if missed[1] then
		ns.Print(("Give %s to %s."):format(ns.ItemLink(item), table.concat(missed, ", ")))
	end
end
