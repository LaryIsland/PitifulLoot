local _, ns = ...

-- The ledger's messages (`Notes/Ledger Format.md`, section 2), built with Pack.lua. Each Write or Encode has a Read
-- that takes a reader (ns.NewReader); Reads raise on anything malformed, so call them through ns.Decode for bytes
-- that came from another player.

local NONE = 7 -- a pity grid's "no cell"
local UNKNOWN_ROLE = 3
local NO_SIG = string.rep("\0", 8)

local function Sorted(set)
	local list = {}
	for key in pairs(set) do list[#list + 1] = key end
	table.sort(list)
	return list
end

local function CheckCell(cell, allowWon)
	if cell > (allowWon and ns.CELL_WON or ns.CELL_WON - 1) then error("bad cell", 0) end
	return cell
end

-- 2.2 Rows -----------------------------------------------------------------------------------------------------------

-- A player's sub-row as it's signed: GUID, raid, version, key, then its items in ascending order and their cells.
-- Officers sign exactly these bytes, so a row checks out however it travelled.
function ns.RowContent(guid, raid, sub)
	local items = Sorted(sub.cells)
	local cells = {}
	for i, item in ipairs(items) do cells[i] = sub.cells[item] end
	local w = ns.NewWriter():Str8(guid):Str8(raid):U32(sub.version or 0):U8(sub.key or 0):U16(#items)
	for _, item in ipairs(items) do w:U24(item) end
	return w:Bits(cells, 3):Result()
end

-- The first 8 bytes of a sub-row's SHA-256, for the row check (2.7).
function ns.RowHash(guid, raid, sub)
	return ns.SHA256(ns.RowContent(guid, raid, sub)):sub(1, 8)
end

-- A sub-row with its signature (8 zero bytes if it hasn't been signed).
function ns.EncodeRow(guid, raid, sub)
	return ns.RowContent(guid, raid, sub) .. (sub.sig or NO_SIG)
end

function ns.ReadRow(r)
	local guid, raid = r:Str8(), r:Str8()
	local sub = { version = r:U32(), key = r:U8(), cells = {} }
	local count = r:U16()
	local items = {}
	for i = 1, count do items[i] = r:U24() end
	for i, cell in ipairs(r:Bits(count, 3)) do sub.cells[items[i]] = CheckCell(cell, true) end
	sub.sig = r:Bytes(8)
	if sub.key == 0 then sub.key, sub.sig = nil, nil end
	return guid, raid, sub
end

-- 2.3 A roll's pool ----------------------------------------------------------------------------------------------

-- The pity of everyone in the raid with some on the item, as { guid, cell } pairs (cells 0 to 4: winners aren't in it).
function ns.EncodePool(item, pool)
	local guids = {}
	for i, entry in ipairs(pool) do guids[i] = entry[1] end
	local prefix = ns.GuidPrefix(guids)
	local w = ns.NewWriter():U24(item):Str8(prefix):U8(#pool)
	local cells = {}
	for i, entry in ipairs(pool) do
		w:Guid(entry[1], prefix)
		cells[i] = entry[2]
	end
	return w:Bits(cells, 3):Result()
end

function ns.ReadPool(r)
	local item, prefix, count = r:U24(), r:Str8(), r:U8()
	local guids, pool = {}, {}
	for i = 1, count do guids[i] = r:Guid(prefix) end
	for i, cell in ipairs(r:Bits(count, 3)) do pool[i] = { guids[i], CheckCell(cell, false) } end
	return item, pool
end

-- 2.5 The item table -----------------------------------------------------------------------------------------------

-- The item table, or only the raids named in `only` (a set of raid names).
function ns.WriteItems(w, items, only)
	local raids = {}
	for _, raid in ipairs(items.raids) do
		if not only or only[raid.name] then raids[#raids + 1] = raid end
	end
	w:U8(#raids)
	for _, raid in ipairs(raids) do
		w:Str8(raid.name):U8(#raid.bosses)
		for _, boss in ipairs(raid.bosses) do
			w:Str8(boss.name):U16(#boss.items)
			for _, item in ipairs(boss.items) do w:U24(item):U8(items.roles[item] or 0) end
		end
	end
	return w
end

function ns.EncodeItems(items, only)
	return ns.WriteItems(ns.NewWriter(), items, only):Result()
end

function ns.ReadItems(r)
	local items = { raids = {}, roles = {} }
	for i = 1, r:U8() do
		local raid = { name = r:Str8(), bosses = {} }
		items.raids[i] = raid
		for j = 1, r:U8() do
			local boss = { name = r:Str8(), items = {} }
			raid.bosses[j] = boss
			for k = 1, r:U16() do
				local item, roles = r:U24(), r:U8()
				if roles > 7 then error("bad roles", 0) end
				boss.items[k] = item
				items.roles[item] = roles ~= 0 and roles or nil
			end
		end
	end
	return items
end

-- 2.4 The whole table ----------------------------------------------------------------------------------------------

local function RaidItems(raid)
	local list = {}
	for _, boss in ipairs(raid.bosses) do
		for _, item in ipairs(boss.items) do list[#list + 1] = item end
	end
	return list
end

-- Everything after the head: the guild list (every GUID the table mentions, sorted), last known roles, the item table,
-- a pity grid per raid, and the leavers. `meta` adds each sub-row's version; the table's hash leaves it out, so copies
-- with the same content hash the same. Signatures aren't sent: officers share the key, so each signs rows itself.
local function WriteContent(w, data, meta)
	local set = {}
	for _, map in ipairs({ data.rows, data.roles, data.leavers }) do
		for guid in pairs(map) do set[guid] = true end
	end
	local guids, place = Sorted(set), {}
	for i, guid in ipairs(guids) do place[guid] = i end
	local prefix = ns.GuidPrefix(guids)
	w:Str8(prefix):U16(#guids)
	for _, guid in ipairs(guids) do w:Guid(guid, prefix) end
	local roles = {}
	for i, guid in ipairs(guids) do roles[i] = data.roles[guid] or UNKNOWN_ROLE end
	w:Bits(roles, 2)
	ns.WriteItems(w, data.items)
	for _, raid in ipairs(data.items.raids) do
		local items, holders = RaidItems(raid), {}
		for i, guid in ipairs(guids) do
			if data.rows[guid] and data.rows[guid][raid.name] then holders[#holders + 1] = i end
		end
		w:U16(#holders)
		for _, i in ipairs(holders) do
			local sub = data.rows[guids[i]][raid.name]
			w:U16(i)
			if meta then w:U32(sub.version or 0) end
			local cells = {}
			for j, item in ipairs(items) do cells[j] = sub.cells[item] or NONE end
			w:Bits(cells, 3)
		end
	end
	local leavers = Sorted(data.leavers)
	w:U16(#leavers)
	for _, guid in ipairs(leavers) do w:U16(place[guid]):U32(data.leavers[guid]) end
	return w
end

-- The first 16 bytes of SHA-256 over the table's content (6.1).
function ns.TableHash(ledger)
	return ns.SHA256(WriteContent(ns.NewWriter(), ledger.data, false):Result()):sub(1, 16)
end

-- The whole table, for officers: the head (hash, revision, who changed it), then the content with each sub-row's
-- version. The rows arrive unsigned; the officer signs them with the current key (Ledger:Sign).
function ns.PackTable(ledger)
	local head = ledger.data.head
	local hash = #head.hash == 16 and head.hash or string.rep("\0", 16)
	local w = ns.NewWriter():Bytes(hash):U32(head.rev):Str8(head.by or "")
	return WriteContent(w, ledger.data, true):Result()
end

-- A table's data (for ns.NewLedger) from ns.PackTable's bytes.
function ns.ReadTable(r)
	local data = { head = { hash = r:Bytes(16), rev = r:U32(), by = r:Str8() }, rows = {}, roles = {}, leavers = {} }
	local prefix = r:Str8()
	local count = r:U16()
	local guids = {}
	for i = 1, count do guids[i] = r:Guid(prefix) end
	for i, code in ipairs(r:Bits(count, 2)) do
		if code ~= UNKNOWN_ROLE then data.roles[guids[i]] = code end
	end
	data.items = ns.ReadItems(r)
	for _, raid in ipairs(data.items.raids) do
		local items = RaidItems(raid)
		for _ = 1, r:U16() do
			local guid = guids[r:U16()] or error("bad place", 0)
			local sub = { version = r:U32(), cells = {} }
			for j, cell in ipairs(r:Bits(#items, 3)) do
				if cell ~= NONE then sub.cells[items[j]] = CheckCell(cell, true) end
			end
			data.rows[guid] = data.rows[guid] or {}
			data.rows[guid][raid.name] = sub
		end
	end
	for _ = 1, r:U16() do
		local guid = guids[r:U16()] or error("bad place", 0)
		data.leavers[guid] = r:U32()
	end
	return data
end

-- 2.6 Officers' changes (diffs) -----------------------------------------------------------------------------------

-- A change is { op, time, by, n, ... }: adjust {id, item, steps (-5 to +5 tens), unlock, won}; result {item, raid, boss, losers, winners}
-- (what happened, not the cells it left, so two raids' results merge without counting anything twice; raid and boss
-- "" for none or trash); leave {id} (time is the leave date); rejoin {id}; itemroles {item, roles}; role {id, role}.
local OPS = { adjust = 1, result = 2, leave = 3, rejoin = 4, itemroles = 5, role = 6 }
local OP_NAMES = {}
for name, code in pairs(OPS) do OP_NAMES[code] = name end
local STEPS, UNLOCK, WON = 5, 128, 64 -- an adjustment's steps (-5 to +5) go as 0 to 10; 128 is added to lift a win,
-- and 64 to record one

function ns.EncodeDiffs(diffs)
	local guids = {}
	for _, d in ipairs(diffs) do
		guids[#guids + 1] = d.by
		if d.id then guids[#guids + 1] = d.id end
		for _, id in ipairs(d.losers or {}) do guids[#guids + 1] = id end
		for _, id in ipairs(d.winners or {}) do guids[#guids + 1] = id end
	end
	local prefix = ns.GuidPrefix(guids)
	local w = ns.NewWriter():Str8(prefix):U16(#diffs)
	for _, d in ipairs(diffs) do
		w:U8(OPS[d.op] or error("unknown op " .. tostring(d.op)))
		if d.op == "adjust" then
			w:Guid(d.id, prefix):U24(d.item):U8(d.steps + STEPS + (d.unlock and UNLOCK or 0) + (d.won and WON or 0))
		elseif d.op == "result" then
			w:U24(d.item):Str8(d.raid or ""):Str8(d.boss or ""):U8(#d.losers)
			for _, id in ipairs(d.losers) do w:Guid(id, prefix) end
			w:U8(#d.winners)
			for _, id in ipairs(d.winners) do w:Guid(id, prefix) end
		elseif d.op == "leave" or d.op == "rejoin" then
			w:Guid(d.id, prefix)
		elseif d.op == "itemroles" then
			w:U24(d.item):U8(d.roles)
		elseif d.op == "role" then
			w:Guid(d.id, prefix):U8(d.role or UNKNOWN_ROLE)
		end
		w:U32(d.time):U16(d.n or 0):Guid(d.by, prefix)
	end
	return w:Result()
end

function ns.ReadDiffs(r)
	local prefix = r:Str8()
	local diffs = {}
	for i = 1, r:U16() do
		local d = { op = OP_NAMES[r:U8()] or error("unknown op", 0) }
		if d.op == "adjust" then
			d.id, d.item = r:Guid(prefix), r:U24()
			local code = r:U8()
			if code >= UNLOCK then d.unlock, code = true, code - UNLOCK end
			if code >= WON then d.won, code = true, code - WON end
			if code > 2 * STEPS then error("bad steps", 0) end
			d.steps = code - STEPS
		elseif d.op == "result" then
			d.item, d.raid, d.boss, d.losers, d.winners = r:U24(), r:Str8(), r:Str8(), {}, {}
			for j = 1, r:U8() do d.losers[j] = r:Guid(prefix) end
			for j = 1, r:U8() do d.winners[j] = r:Guid(prefix) end
		elseif d.op == "leave" or d.op == "rejoin" then
			d.id = r:Guid(prefix)
		elseif d.op == "itemroles" then
			d.item, d.roles = r:U24(), r:U8()
			if d.roles > 7 then error("bad roles", 0) end
		elseif d.op == "role" then
			d.id = r:Guid(prefix)
			local role = r:U8()
			if role > UNKNOWN_ROLE then error("bad role", 0) end
			if role ~= UNKNOWN_ROLE then d.role = role end
		end
		d.time, d.n, d.by = r:U32(), r:U16(), r:Guid(prefix)
		diffs[i] = d
	end
	return diffs
end

-- 2.7 The row check --------------------------------------------------------------------------------------------------

-- Each of a player's sub-rows (raid -> sub-row), by raid: its version and the first 8 bytes of its hash.
function ns.EncodeRowCheck(guid, subs)
	local raids = Sorted(subs)
	local w = ns.NewWriter():U8(#raids)
	for _, raid in ipairs(raids) do
		local sub = subs[raid]
		w:Str8(raid):U32(sub.version or 0):Bytes(ns.RowHash(guid, raid, sub))
	end
	return w:Result()
end

function ns.ReadRowCheck(r)
	local checks = {}
	for i = 1, r:U8() do checks[i] = { raid = r:Str8(), version = r:U32(), hash = r:Bytes(8) } end
	return checks
end
