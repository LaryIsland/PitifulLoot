local _, ns = ...

-- Each boss's loot, shared with the whole group (5.1). The officer who loots it (the master looter) sends the list to
-- the group, and every client follows each item through its roll from the writer's messages: rolling, won, awarded
-- to whom, or no one rolled. Each boss's loot is a group, kept in the order it was seen until you leave the group.
-- Only the writer starts rolls from it, and the master looter's client hands items to the winners.

local LIVE = ns.PREFIX_LIVE
local MAX_CANDIDATES = 40

-- ns.loot.groups: { key, boss, from, items = { item, copies, boe, status, sid, winners, pending } }, oldest first;
-- status is "waiting", "rolling", "decided", "none" (no one rolled) or "awarded".
ns.loot = { groups = {} }
local given = {}

local function Scan()
	local items, byItem = {}, {}
	for slot = 1, GetNumLootItems() do
		local link = LootSlotHasItem(slot) and GetLootSlotLink(slot)
		local item = link and ns.ItemID(link)
		local quality = select(5, GetLootSlotInfo(slot))
		if item and quality and quality >= ns.settings.minQuality then
			if not byItem[item] then
				byItem[item] = { item = item, copies = 0, boe = ns.IsBoE(item) or nil }
				items[#items + 1] = byItem[item]
			end
			byItem[item].copies = byItem[item].copies + 1
		end
	end
	return items
end

local function KeyOf(items)
	local parts = {}
	for i, entry in ipairs(items) do parts[i] = entry.item .. "x" .. entry.copies end
	table.sort(parts)
	return table.concat(parts, ",")
end

function ns.LatestLoot()
	return ns.loot.groups[#ns.loot.groups]
end

-- Adds a boss's loot as a new group. Opening the same loot again keeps where each item has got to, unless `fresh`.
function ns.SetLoot(items, from, boss, fresh)
	local key = KeyOf(items)
	if not fresh then
		for _, group in ipairs(ns.loot.groups) do
			if group.key == key then return false end
		end
	end
	for _, entry in ipairs(items) do
		entry.status, entry.sid, entry.winners = "waiting", nil, {}
	end
	local group = { key = key .. "#" .. (#ns.loot.groups + 1), boss = boss, from = from, items = items }
	table.insert(ns.loot.groups, group)
	ns.Capture("loot", group)
	ns.Fire("LOOT_CHANGED", group)
	return true
end

-- Sends the newest loot to the group, so everyone sees what dropped.
function ns.ShareLoot()
	local group = ns.LatestLoot()
	if not IsInGroup() or not group then return end
	local items = {}
	for i, entry in ipairs(group.items) do items[i] = { item = entry.item, copies = entry.copies, boe = entry.boe } end
	ns.Send(LIVE, "loot", { items = items, boss = group.boss }, IsInRaid() and "RAID" or "PARTY")
end

-- Who dropped it: the boss last killed here, or the corpse being looted.
local function LootedBoss()
	local boss = ns.LastBoss()
	if boss then return boss end
	if UnitExists("target") and UnitIsDead("target") and not UnitIsPlayer("target") then return (UnitName("target")) end
end

ns.On("LOOT_OPENED", function()
	given = {}
	if not ns.IsOfficer(ns.PlayerName()) then return end
	local items = Scan()
	if items[1] and ns.SetLoot(items, ns.PlayerName(), LootedBoss()) then ns.ShareLoot() end
end)
ns.On("LOOT_CLOSED", function() given = {} end)

ns.Receive(LIVE, "loot", function(d, sender)
	if type(d) ~= "table" or type(d.items) ~= "table" or not ns.IsOfficer(sender) then return end
	local items = {}
	for _, entry in ipairs(d.items) do
		if type(entry) == "table" and type(entry.item) == "number" and type(entry.copies) == "number" then
			items[#items + 1] = { item = entry.item, copies = entry.copies, boe = entry.boe and true or nil }
		end
	end
	ns.SetLoot(items, sender, type(d.boss) == "string" and d.boss or nil)
end)

-- A late joiner's copy of the loot, statuses included, from the writer's reply to their query.
function ns.RestoreLoot(loot)
	if type(loot) ~= "table" or type(loot.groups) ~= "table" then return end
	for _, group in ipairs(loot.groups) do
		if type(group) ~= "table" or type(group.items) ~= "table" then return end
		for _, entry in ipairs(group.items) do
			if type(entry) ~= "table" or type(entry.item) ~= "number" then return end
			entry.winners = type(entry.winners) == "table" and entry.winners or {}
		end
	end
	ns.loot = loot
	ns.Fire("LOOT_CHANGED", ns.LatestLoot())
end

-- The loot entry a roll is for: the one it started on, or else the newest of that item still to be given out.
local function EntryFor(m)
	local groups = ns.loot.groups
	for g = #groups, 1, -1 do
		for _, entry in ipairs(groups[g].items) do
			if entry.sid == m.sid then return entry end
		end
	end
	for g = #groups, 1, -1 do
		for _, entry in ipairs(groups[g].items) do
			if entry.item == m.item and not entry.sid and entry.status ~= "awarded" then return entry end
		end
	end
end

-- Follows each item through its roll, from the same writer's messages that drive the roll page.
ns.Listen("ROLL_EVENT", function(kind, m)
	local entry = m and EntryFor(m)
	if not entry then return end
	if kind == "open" or (kind == "state" and (m.state == "open" or m.state == "reroll")) then
		entry.sid, entry.status = m.sid, "rolling"
	elseif kind == "decided" then
		entry.status = m.winners[1] and "decided" or "none"
		if not m.winners[1] then entry.sid = nil end
		entry.pending = m.winners
	elseif kind == "awarded" then
		for _, id in ipairs(m.winners) do table.insert(entry.winners, id) end
		entry.status = #entry.winners >= entry.copies and "awarded" or "waiting"
		entry.sid, entry.pending = nil, nil
	elseif kind == "cancel" then
		entry.status = "waiting"
		entry.sid, entry.pending = nil, nil
	end
	ns.Fire("LOOT_CHANGED")
end)

ns.On("GROUP_ROSTER_UPDATE", function()
	if not IsInGroup() and not ns.IsTestMode() and ns.loot.groups[1] then
		ns.loot = { groups = {} }
		ns.Fire("LOOT_CHANGED")
	end
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
