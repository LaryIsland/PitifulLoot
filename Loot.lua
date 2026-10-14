local _, ns = ...

-- Each boss's loot, shared with the whole group (5.1). The officer who loots it (the master looter) sends the list to
-- the group, and every client follows each item through its roll from the writer's messages: rolling, won, awarded
-- to whom, or no one rolled. Each boss's loot is a group, kept in the order it was seen until you leave the group.
-- Only the writer starts rolls from it, and the master looter's client hands items to the winners.

local LIVE = ns.PREFIX_LIVE
local MAX_CANDIDATES = 40

-- ns.loot.groups: { key, source, contents, boss, from, time, items = { item, copies, boe, status, sid, winners,
-- pending, handovers } }, oldest first. `source` is the GUID of the corpse or chest it came from, if the game says.
-- status is "waiting", "rolling", "decided", "none" (no one rolled), "awarded", "disenchanted" or "kept" (to sell).
-- `time` is when it was looted, which starts the time it can be traded in. Each copy awarded has a handover,
-- { id, sid, done }, done once the winner has it: given by master loot, or traded (Trades.lua).
ns.loot = { groups = {} }
local given = {}

-- The loot on show worth rolling for, and the GUID of what it's being looted from.
local function Scan()
	local items, byItem, source = {}, {}, nil
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
			local guid = source or GetLootSourceInfo(slot)
			if canaccessvalue(guid) and type(guid) == "string" then source = guid end
		end
	end
	return items, source
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

-- Adds a boss's loot as a new group (`trash` if it came from trash). Opening the same loot again keeps where each item
-- has got to, unless `fresh`. The same loot is the same corpse, even once some of it has been handed out, or failing
-- that the same items.
function ns.SetLoot(items, from, boss, fresh, time, source, trash)
	local key = KeyOf(items)
	if not fresh then
		for _, group in ipairs(ns.loot.groups) do
			if source and group.source == source or not source and group.contents == key then return false end
		end
	end
	for _, entry in ipairs(items) do
		entry.status, entry.sid, entry.winners, entry.handovers = "waiting", nil, {}, {}
	end
	local group = {
		key = key .. "#" .. (#ns.loot.groups + 1), source = source, contents = key, boss = boss, from = from,
		time = time or GetServerTime(), items = items, trash = trash or nil,
	}
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
	ns.Send(LIVE, "loot", { items = items, boss = group.boss, time = group.time, source = group.source, trash = group.trash },
		IsInRaid() and "RAID" or "PARTY")
end

-- The bosses of the encounter under way or just ended, by GUID, from the boss unit frames, so loot from one of their
-- corpses is that boss's and loot from any other corpse in a raid is trash (6.1).
local bosses = {}
local function NoteBosses()
	for i = 1, 5 do
		local guid = UnitGUID("boss" .. i)
		if canaccessvalue(guid) and guid then bosses[guid] = true end
	end
end
ns.On("ENCOUNTER_START", function()
	bosses = {}
	NoteBosses()
end)
ns.On("INSTANCE_ENCOUNTER_ENGAGE_UNIT", NoteBosses)

-- Who dropped it: the boss last killed here if the corpse is one of its bosses, or false for trash in a raid; without
-- a corpse to go by (or before any boss here), the boss last killed here, or the corpse being looted.
local function LootedBoss(source)
	local _, instanceType = GetInstanceInfo()
	if source and next(bosses) and instanceType == "raid" then
		return bosses[source] and ns.LastBoss() or false
	end
	local boss = ns.LastBoss()
	if boss then return boss end
	if UnitExists("target") and UnitIsDead("target") and not UnitIsPlayer("target") then return (UnitName("target")) end
end

ns.On("LOOT_OPENED", function()
	given = {}
	if not ns.IsOfficer(ns.PlayerName()) then return end
	local items, source = Scan()
	local boss = LootedBoss(source)
	if items[1] and ns.SetLoot(items, ns.PlayerName(), boss or nil, false, nil, source, boss == false) then ns.ShareLoot() end
end)

-- Where the newest loot with an item still to roll for came from: its boss, false for trash, or nil if not known.
function ns.LootBossOf(item)
	local groups = ns.loot.groups
	for g = #groups, 1, -1 do
		for _, entry in ipairs(groups[g].items) do
			if entry.item == item and not ns.LootDone(entry) then
				if groups[g].trash then return false end
				return groups[g].boss
			end
		end
	end
end
ns.On("LOOT_CLOSED", function() given = {} end)

ns.Receive(LIVE, "loot", function(d, sender)
	if type(d) ~= "table" or type(d.items) ~= "table" or not ns.IsOfficer(sender) then return end
	local items = {}
	for _, entry in ipairs(d.items) do
		if type(entry) == "table" and type(entry.item) == "number" and type(entry.copies) == "number" then
			items[#items + 1] = { item = entry.item, copies = entry.copies, boe = entry.boe and true or nil }
		end
	end
	ns.SetLoot(items, sender, type(d.boss) == "string" and d.boss or nil, false, type(d.time) == "number" and d.time or nil,
		type(d.source) == "string" and d.source or nil, d.trash == true)
end)

-- A late joiner's copy of the loot, statuses included, from the writer's reply to their query; or the loot saved
-- when you last logged out or reloaded, through `filter`.
function ns.RestoreLoot(loot, filter)
	if type(loot) ~= "table" or type(loot.groups) ~= "table" then return end
	for _, group in ipairs(loot.groups) do
		if type(group) ~= "table" or type(group.items) ~= "table" then return end
		if type(group.time) ~= "number" then group.time = GetServerTime() end
		for _, entry in ipairs(group.items) do
			if type(entry) ~= "table" or type(entry.item) ~= "number" then return end
			entry.winners = type(entry.winners) == "table" and entry.winners or {}
			entry.handovers = type(entry.handovers) == "table" and entry.handovers or {}
		end
	end
	ns.loot = filter and filter(loot) or loot
	ns.Fire("LOOT_CHANGED", ns.LatestLoot(), true)
end

-- The loot entry a roll is for, and its group: the one it started on, or else the newest of that item still to be
-- given out.
local function EntryFor(m)
	local groups = ns.loot.groups
	for g = #groups, 1, -1 do
		for _, entry in ipairs(groups[g].items) do
			if entry.sid == m.sid or entry.lastSid == m.sid then return entry, groups[g] end
		end
	end
	for g = #groups, 1, -1 do
		for _, entry in ipairs(groups[g].items) do
			if entry.item == m.item and not entry.sid and not ns.LootDone(entry) then
				return entry, groups[g]
			end
		end
	end
end

-- Whether the winner is the officer who looted the group, and so already has their copy.
local function Holds(group, id)
	local holder = group.from and ns.GroupMember(group.from)
	if holder then return holder.guid == id end
	return ns.SameName(group.from, ns.NameOf(id))
end

-- Follows each item through its roll, from the same writer's messages that drive the roll page.
ns.Listen("ROLL_EVENT", function(kind, m)
	local entry, group = nil, nil
	if m then entry, group = EntryFor(m) end
	if not entry then return end
	if kind == "open" or (kind == "state" and (m.state == "open" or m.state == "reroll")) then
		entry.sid, entry.status = m.sid, "rolling"
	elseif kind == "decided" then
		entry.status = m.winners[1] and "decided" or "none"
		if not m.winners[1] then entry.sid, entry.lastSid = nil, m.sid end
		entry.pending = m.winners
	elseif kind == "awarded" then
		-- A copy given by master loot, or won by the officer holding it, has nothing left to hand over.
		local given = {}
		for _, id in ipairs(m.given or {}) do given[id] = true end
		for _, id in ipairs(m.winners) do
			table.insert(entry.winners, id)
			table.insert(entry.handovers, { id = id, sid = m.sid, done = (given[id] or Holds(group, id)) or nil })
		end
		entry.status = #entry.winners >= entry.copies and "awarded" or "waiting"
		entry.sid, entry.pending = nil, nil
	elseif kind == "disenchant" then
		entry.status = m.state == "kept" and "kept" or "disenchanted"
		entry.sid, entry.lastSid, entry.pending = nil, nil, nil
	elseif kind == "cancel" then
		entry.status = "waiting"
		entry.sid, entry.pending = nil, nil
	end
	ns.Fire("LOOT_CHANGED")
end)

-- Whether an item's been dealt with: awarded in full, disenchanted, or kept to sell.
function ns.LootDone(entry)
	return entry.status == "awarded" or entry.status == "disenchanted" or entry.status == "kept"
end

-- Loot is kept through a /reload or logging out (each character's own), and after leaving the group while copies are
-- still to be handed over, so the items awaiting trade aren't lost. Loot older than the trade window is let go; out
-- of a group, so is loot with nothing left to hand over.
local function StillNeeded(group, grouped)
	if GetServerTime() - group.time > ns.TRADE_WINDOW then return false end
	if grouped then return true end
	for _, entry in ipairs(group.items) do
		for _, handover in ipairs(entry.handovers) do
			if not handover.done then return true end
		end
	end
	return false
end

local function Prune(loot, grouped)
	local kept = {}
	for _, group in ipairs(loot.groups) do
		if StillNeeded(group, grouped) then kept[#kept + 1] = group end
	end
	loot.groups = kept
	return loot
end

ns.On("GROUP_ROSTER_UPDATE", function()
	if not IsInGroup() and not ns.IsTestMode() and ns.loot.groups[1] then
		local before = #ns.loot.groups
		Prune(ns.loot, false)
		if #ns.loot.groups ~= before then ns.Fire("LOOT_CHANGED") end
	end
end)

local loaded = false
ns.On("PLAYER_ENTERING_WORLD", function()
	if loaded then return end
	loaded = true
	local saved = ns.saved.loot and ns.saved.loot[UnitGUID("player")]
	if type(saved) == "table" and type(saved.groups) == "table" then
		ns.RestoreLoot(saved, function(loot) return Prune(loot, IsInGroup() or ns.IsTestMode()) end)
	end
end)

ns.On("PLAYER_LOGOUT", function()
	ns.saved.loot = ns.saved.loot or {}
	ns.saved.loot[UnitGUID("player")] = ns.loot.groups[1] and ns.loot or nil
end)

-- Candidates are matched to the winner by GUID, as a candidate's name may or may not include their surname.
local function GiveTo(item, id)
	for slot = 1, GetNumLootItems() do
		if not given[slot] and LootSlotHasItem(slot) and ns.ItemID(GetLootSlotLink(slot)) == item then
			for i = 1, MAX_CANDIDATES do
				local candidate = ns.GroupMember(GetMasterLootCandidate(slot, i))
				if candidate and candidate.guid == id then
					GiveMasterLoot(slot, i)
					given[slot] = true -- the slot clears later, so don't hand it out twice meanwhile
					return true
				end
			end
		end
	end
	return false
end

-- Gives each winner a copy when this client is the master looter with the loot open; otherwise says who gets it,
-- unless `quiet`. Returns the winners given theirs.
function ns.GiveLoot(item, winners, quiet)
	local given, missed = {}, {}
	for _, id in ipairs(winners) do
		if IsMasterLooter() and GiveTo(item, id) then
			given[#given + 1] = id
		else
			missed[#missed + 1] = ns.NameOf(id)
		end
	end
	if missed[1] and not quiet then
		ns.Print(ns.L.MSG_GIVE:format(ns.ItemLink(item), table.concat(missed, ", ")))
	end
	return given
end

-- Whether there's still loot to deal with: an item to roll for, or a copy won but not yet handed over.
function ns.LootToDistribute()
	for _, group in ipairs(ns.loot.groups) do
		for _, entry in ipairs(group.items) do
			if entry.status == "waiting" or entry.status == "none" then return true end
			for _, handover in ipairs(entry.handovers) do
				if not handover.done then return true end
			end
		end
	end
	return false
end
