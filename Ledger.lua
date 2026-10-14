local _, ns = ...

-- The ledger (design document 6.1, `Notes/Ledger Format.md`): a guild's pity as it stands, not its history.
--
--   rows     guid -> raid -> { version, key, sig, cells = { item -> cell } }    a sub-row per raid ("" is raidless)
--   items    { raids = { { name, bosses = { { name, items = { item... } } } } }, roles = { item -> role bits } }
--   roles    guid -> last known role (0 tank, 1 healer, 2 damage; missing: not known yet)
--   leavers  guid -> when they left (server time)
--   head     { hash, rev, by }
--
-- A cell is 0 to 4 for +10 to +50, or 5 for won. No cell, no pity.

local WON, MAX = 5, 4
local WEEK = 7 * 24 * 60 * 60
local CATCH_ALL = "" -- a raid's catch-all boss (its trash loot) is named this, as is the raidless catch-all raid

ns.CELL_WON = WON
ns.CATCH_ALL = CATCH_ALL
ns.ROLE_CODES = { TANK = 0, HEALER = 1, DAMAGER = 2 }
ns.ROLE_BITS = { TANK = 1, HEALER = 2, DAMAGER = 4 }

local Ledger = {}
Ledger.__index = Ledger

-- A ledger over `data` (the table kept in saved variables), or a new empty one.
function ns.NewLedger(data)
	data = data or {}
	data.head = data.head or { hash = "", rev = 0, by = "" }
	data.rows = data.rows or {}
	data.items = data.items or { raids = {}, roles = {} }
	data.roles = data.roles or {}
	data.leavers = data.leavers or {}
	-- doubles: double wins found while applying changes, for Pity.lua to report; wonBy: the change that first gave each
	-- win this table has seen applied ("guid:item" -> change).
	local w = setmetatable({ data = data, changed = {}, doubles = {}, wonBy = {} }, Ledger)
	w:Reindex()
	return w
end

-- The item table ----------------------------------------------------------------------------------------------------

-- Where each item is: its raid and boss entries in the item table.
function Ledger:Reindex()
	self.where = {}
	for _, raid in ipairs(self.data.items.raids) do
		for _, boss in ipairs(raid.bosses) do
			for _, item in ipairs(boss.items) do self.where[item] = { raid = raid, boss = boss } end
		end
	end
end

-- The raid an item's cells are kept under ("" for the raidless catch-all, or an item not in the table).
function Ledger:RaidOf(item)
	local at = self.where[item]
	return at and at.raid.name or CATCH_ALL
end

-- The drop location of an item, as raid and boss names ("" for a catch-all), or nil if it isn't known.
function Ledger:Source(item)
	local at = self.where[item]
	if at then return at.raid.name, at.boss.name end
end

local function Find(list, name)
	for _, entry in ipairs(list) do
		if entry.name == name then return entry end
	end
end

-- Adds a named entry, keeping a catch-all (named "") last.
local function Add(list, entry)
	local last = list[#list]
	if entry.name ~= CATCH_ALL and last and last.name == CATCH_ALL then
		table.insert(list, #list, entry)
	else
		list[#list + 1] = entry
	end
	return entry
end

local function Remove(list, value)
	for i, v in ipairs(list) do
		if v == value then return table.remove(list, i) end
	end
end

-- Moves an item to a raid and boss, creating them as needed, and its cells with it if its raid changes.
function Ledger:Place(item, raidName, bossName)
	local raids = self.data.items.raids
	local from = self.where[item]
	if from then
		Remove(from.boss.items, item)
		if not from.boss.items[1] then Remove(from.raid.bosses, from.boss) end
		if not from.raid.bosses[1] then Remove(raids, from.raid) end
	end
	local raid = Find(raids, raidName) or Add(raids, { name = raidName, bosses = {} })
	local boss = Find(raid.bosses, bossName) or Add(raid.bosses, { name = bossName, items = {} })
	boss.items[#boss.items + 1] = item
	self.where[item] = { raid = raid, boss = boss }
	local oldRaid = from and from.raid.name or CATCH_ALL
	if oldRaid ~= raidName then
		local moving = {}
		for guid, subs in pairs(self.data.rows) do
			local sub = subs[oldRaid]
			if sub and sub.cells[item] then moving[guid] = sub.cells[item] end
		end
		for guid, cell in pairs(moving) do
			self:Store(guid, oldRaid, item, nil)
			self:Store(guid, raidName, item, cell)
		end
	end
end

-- Records where an item dropped (6.1): `raid` is the raid instance it was looted in, or nil outside one; `boss` the
-- boss it came from, or nil for trash. A boss's loot goes under that boss; trash under its raid's catch-all; loot from
-- outside raids, or trash already in another raid's catch-all, under the raidless catch-all. An item in a catch-all
-- that's later seen from a boss moves to that boss. Returns whether the item table changed.
function Ledger:Learn(item, raid, boss)
	if raid == CATCH_ALL then raid = nil end
	if boss == CATCH_ALL then boss = nil end
	local raidName = raid or CATCH_ALL
	local bossName = raid and boss or CATCH_ALL
	local at = self.where[item]
	if at then
		if at.raid.name == raidName and at.boss.name == bossName then return false end
		if at.boss.name ~= CATCH_ALL then return false end -- a boss's loot stays its boss's
		if bossName == CATCH_ALL then
			if at.raid.name == CATCH_ALL then return false end
			raidName = CATCH_ALL -- trash in a second raid, or seen outside raids
		end
	end
	self:Place(item, raidName, bossName)
	return true
end

-- An officer's say on the roles an item is main-spec for (4.6), as role bits; nil or 0 goes back to its stats.
function Ledger:SetItemRoles(item, bits)
	self.data.items.roles[item] = bits ~= 0 and bits or nil
end

function Ledger:ItemRoles(item)
	return self.data.items.roles[item]
end

-- Rows ------------------------------------------------------------------------------------------------------------

-- Sets or clears one cell in a player's sub-row, dropping empty sub-rows and rows, and notes the sub-row changed.
function Ledger:Store(guid, raid, item, cell)
	local rows = self.data.rows
	local subs = rows[guid]
	if cell == nil and not (subs and subs[raid]) then return end
	subs = subs or {}
	rows[guid] = subs
	local sub = subs[raid] or { version = 0, cells = {} }
	subs[raid] = sub
	sub.cells[item] = cell
	if next(sub.cells) == nil then subs[raid] = nil end
	if next(subs) == nil then rows[guid] = nil end
	self.changed[guid] = self.changed[guid] or {}
	self.changed[guid][raid] = true
end

-- A player's cell for an item. Officers' tables keep it under the item's raid; a member's row holds sub-rows as the
-- officers filed them, which can differ from the member's own item table, so the other sub-rows are looked in too.
function Ledger:Cell(guid, item)
	local subs = self.data.rows[guid]
	if not subs then return nil end
	local sub = subs[self:RaidOf(item)]
	if sub and sub.cells[item] then return sub.cells[item] end
	for _, other in pairs(subs) do
		if other.cells[item] then return other.cells[item] end
	end
	return nil
end

-- Sets a cell: 0 to 4 for +10 to +50, 5 for won, nil to clear it. Anything else is refused (4.1).
function Ledger:SetCell(guid, item, cell)
	if cell ~= nil and (type(cell) ~= "number" or cell < 0 or cell > WON or cell % 1 ~= 0) then return false end
	if not self.where[item] then self:Learn(item) end
	self:Store(guid, self:RaidOf(item), item, cell)
	return true
end

-- An officer's adjustment (4.4, 6.4): pity moved by `steps` tens (-5 to +5), kept from 0 to +50. A win stays unless
-- `unlock` lifts it, which brings the player back at 0 before the steps. Adjustments add up in any order with each
-- other and with results, apart from where 0 or +50 cuts them off. `won` records a win by hand instead, as a roll's
-- result would (a win lost in a resync, or a roll the addon didn't run).
function Ledger:Adjust(guid, item, steps, unlock, won)
	if won then return self:SetCell(guid, item, WON) end
	local cell = self:Cell(guid, item)
	if cell == WON then
		if not unlock then return false end
		cell = nil
	end
	local pity = math.max(math.min((cell and cell + 1 or 0) + steps, MAX + 1), 0)
	return self:SetCell(guid, item, pity > 0 and pity - 1 or nil)
end

local function Weeks(left, now)
	return math.max(math.floor((now - left) / WEEK), 0)
end

-- A player's pity on an item by `now` (0 to 50), less any leaver decay due (4.9), and whether they've won it.
function Ledger:Pity(guid, item, now)
	local cell = self:Cell(guid, item)
	if cell == nil then return 0, false end
	if cell == WON then return 0, true end
	local left = self.data.leavers[guid]
	local steps = cell + 1 - (left and now and Weeks(left, now) or 0)
	return math.max(steps, 0) * 10, false
end

-- A need roll's result (4.1, 4.4): every entrant who didn't win gains +10 (to +50), and the winners have won it.
-- Greed rolls change nothing (4.8), so they aren't applied. Returns the cells that changed, as { guid, cell } pairs.
function Ledger:ApplyResult(item, entrants, winners)
	local won, changes = {}, {}
	for _, id in ipairs(winners) do won[id] = true end
	local function Set(id, cell)
		if self:Cell(id, item) ~= cell then
			self:SetCell(id, item, cell)
			changes[#changes + 1] = { id, cell }
		end
	end
	for _, id in ipairs(entrants) do
		local cell = self:Cell(id, item)
		if not won[id] and cell ~= WON then Set(id, cell and math.min(cell + 1, MAX) or 0) end
	end
	for id in pairs(won) do Set(id, WON) end
	return changes
end

-- Leavers (4.9) ----------------------------------------------------------------------------------------------------

-- Records a player leaving the guild at `time`; if it's already recorded, the earliest date stands.
function Ledger:Leave(guid, time)
	local left = self.data.leavers[guid]
	if left and left <= time then return false end
	self.data.leavers[guid] = time
	return true
end

-- A leaver rejoining at `now`: the decay due comes off each item, items at 0 go, and they're no longer a leaver.
function Ledger:Rejoin(guid, now)
	local left = self.data.leavers[guid]
	if not left then return false end
	local weeks = Weeks(left, now)
	for raid, sub in pairs(self.data.rows[guid] or {}) do
		local cells = {}
		for item, cell in pairs(sub.cells) do cells[item] = cell end
		for item, cell in pairs(cells) do
			if cell ~= WON and weeks > 0 then self:Store(guid, raid, item, cell - weeks >= 0 and cell - weeks or nil) end
		end
	end
	self.data.leavers[guid] = nil
	return true
end

-- Drops leavers' items that have decayed to 0, and once all their pity has gone, takes them off the leavers list
-- (4.9). The items they've won stay, so they can't need-roll them again if they come back. Returns the leavers removed.
function Ledger:Tidy(now)
	local removed = {}
	for guid, left in pairs(self.data.leavers) do
		local weeks = Weeks(left, now)
		local pityLeft = false
		for raid, sub in pairs(self.data.rows[guid] or {}) do
			local gone = {}
			for item, cell in pairs(sub.cells) do
				if cell ~= WON then
					if cell + 1 - weeks <= 0 then gone[#gone + 1] = item else pityLeft = true end
				end
			end
			for _, item in ipairs(gone) do self:Store(guid, raid, item, nil) end
		end
		if not pityLeft then removed[#removed + 1] = guid end
	end
	for _, guid in ipairs(removed) do self.data.leavers[guid] = nil end
	return removed
end

-- Last known roles (4.6) --------------------------------------------------------------------------------------------

-- A guild member's last known role, as a role ("TANK", "HEALER", "DAMAGER"), or nil to forget it.
function Ledger:SetLastRole(guid, role)
	self.data.roles[guid] = role and ns.ROLE_CODES[role] or nil
end

function Ledger:LastRole(guid)
	local code = self.data.roles[guid]
	for role, c in pairs(ns.ROLE_CODES) do
		if c == code then return role end
	end
end

-- Revisions and signatures (6.1, 6.3) --------------------------------------------------------------------------------

-- Every sub-row changed since the last stamp gets `time` as its version, and loses its signature until it's signed
-- again. Returns the sub-rows stamped, as { guid, raid } pairs.
function Ledger:Stamp(time)
	local stamped = {}
	for guid, raids in pairs(self.changed) do
		for raid in pairs(raids) do
			local sub = self.data.rows[guid] and self.data.rows[guid][raid]
			if sub then
				sub.version, sub.key, sub.sig = time, nil, nil
				stamped[#stamped + 1] = { guid, raid }
			end
		end
	end
	self.changed = {}
	return stamped
end

-- Makes the changes so far a new revision by the officer `by` at `time`: changed sub-rows are stamped with `time`, and
-- the head's hash is due to be worked out again (Ledger:Hash).
function Ledger:Commit(by, time)
	self:Stamp(time)
	local head = self.data.head
	head.rev, head.by, head.hash = head.rev + 1, by, ""
	return head.rev
end

-- The table's hash (6.1), worked out when something asks for it (sending the whole table, /pl status) rather than on
-- every change: on a big table it takes several frames' worth of time (/pl perf), and nothing else reads it.
function Ledger:Hash()
	local head = self.data.head
	if #head.hash ~= 16 then head.hash = ns.TableHash(self) end
	return head.hash
end

-- Changes (6.4) -------------------------------------------------------------------------------------------------------

-- A change is { op, time, by, n, ... } (LedgerFormat.lua has the ops); `n` tells apart one officer's changes made in
-- the same second. Every officer applies them in the same order, so they all reach the same table.
local function DiffKey(d)
	return d.by .. ":" .. d.time .. ":" .. (d.n or 0)
end
ns.DiffKey = DiffKey

local function DiffBefore(a, b)
	if a.time ~= b.time then return a.time < b.time end
	if a.by ~= b.by then return a.by < b.by end
	return (a.n or 0) < (b.n or 0)
end
ns.DiffBefore = DiffBefore

-- Applies one change. The sub-rows it changes get its time as their version. A roll's result also says where the
-- item dropped ("" for no raid, or for trash), so officers who weren't there learn it too. `only` limits a result to
-- one player: a member keeps only their own row.
function Ledger:ApplyDiff(d, only)
	self.changed = {}
	if d.op == "adjust" then
		self:Adjust(d.id, d.item, d.steps, d.unlock, d.won)
		local at = d.id .. ":" .. d.item
		if d.unlock then self.wonBy[at] = nil end
		if d.won then self.wonBy[at] = self.wonBy[at] or d end
	elseif d.op == "result" then
		local raid = d.raid ~= "" and d.raid or nil
		self:Learn(d.item, raid, raid and d.boss ~= "" and d.boss or nil)
		local entrants, winners = {}, {}
		for _, id in ipairs(d.losers) do
			if not only or id == only then entrants[#entrants + 1] = id end
		end
		for _, id in ipairs(d.winners) do
			if not only or id == only then winners[#winners + 1] = id end
		end
		-- A winner who had already won the item is a double win (6.3): they rolled in a raid whose writer didn't know.
		for _, id in ipairs(winners) do
			local at = id .. ":" .. d.item
			if self:Cell(id, d.item) == WON then
				self.doubles[#self.doubles + 1] = { id = id, item = d.item, change = d, first = self.wonBy[at] }
			end
			self.wonBy[at] = self.wonBy[at] or d
		end
		self:ApplyResult(d.item, entrants, winners)
	elseif d.op == "leave" then
		self:Leave(d.id, d.time)
	elseif d.op == "rejoin" then
		self:Rejoin(d.id, d.time)
	elseif d.op == "itemroles" then
		self:SetItemRoles(d.item, d.roles)
	elseif d.op == "role" then
		self.data.roles[d.id] = d.role
	end
	return self:Stamp(d.time)
end

-- The head (6.1): revision, who made the latest change, and the table's hash (due to be worked out again, Ledger:Hash).
-- The revision counts every change ever applied: the base's, plus the changes since.
function Ledger:UpdateHead()
	local diffs, base = self.data.diffs or {}, self.data.baseHead or { rev = 0, by = "" }
	local head = self.data.head
	head.rev = base.rev + #diffs
	head.by = diffs[#diffs] and diffs[#diffs].by or base.by
	head.hash = ""
end

-- Rebuilds the table from the base and every change since, in order: for a change that arrived out of order, or a new
-- base. Signatures are kept for sub-rows that come out the same.
function Ledger:Rebuild()
	local old = {}
	for guid, subs in pairs(self.data.rows) do
		for raid, sub in pairs(subs) do
			if sub.sig then old[guid .. "\0" .. raid] = { ns.RowContent(guid, raid, sub), sub.key, sub.sig } end
		end
	end
	local base = self.data.base and ns.Decode(ns.ReadTable, self.data.base)
	local fresh = ns.NewLedger(base)
	for _, d in ipairs(self.data.diffs or {}) do fresh:ApplyDiff(d) end
	for _, field in ipairs({ "rows", "items", "roles", "leavers" }) do self.data[field] = fresh.data[field] end
	self.doubles, self.wonBy = fresh.doubles, fresh.wonBy
	self:Reindex()
	for guid, subs in pairs(self.data.rows) do
		for raid, sub in pairs(subs) do
			local was = old[guid .. "\0" .. raid]
			if was then
				sub.key = was[2]
				if ns.RowContent(guid, raid, sub) == was[1] then sub.sig = was[3] else sub.key = nil end
			end
		end
	end
	self.changed = {}
end

-- Adds an officer's change (6.4): applied at once if it's the newest, or by rebuilding if it arrived out of order.
-- Returns whether it was new, and the sub-rows it changed (when applied at once).
function Ledger:AddDiff(d)
	local diffs = self.data.diffs or {}
	self.data.diffs = diffs
	local key = DiffKey(d)
	for _, e in ipairs(diffs) do
		if DiffKey(e) == key then return false end
	end
	local last = diffs[#diffs]
	diffs[#diffs + 1] = d
	local stamped
	if not last or DiffBefore(last, d) then
		stamped = self:ApplyDiff(d)
	else
		table.sort(diffs, DiffBefore)
		self:Rebuild()
	end
	self:UpdateHead()
	return true, stamped
end

-- Whether a change is already held (as a pending change; merged ones are in the base).
function Ledger:HasDiff(key)
	for _, d in ipairs(self.data.diffs or {}) do
		if DiffKey(d) == key then return true end
	end
	return false
end

-- The keys of the pending changes, in order.
function Ledger:DiffKeys()
	local keys = {}
	for i, d in ipairs(self.data.diffs or {}) do keys[i] = DiffKey(d) end
	return keys
end

-- Merges the pending changes whose keys are in `keys` (all of them if nil) into a new base, by `by` at `time` (6.4):
-- leavers whose pity has gone are tidied first, then the table becomes the base and those changes are dropped. Any
-- held change not in `keys` stays pending, on top of the new base. Returns the new revision.
function Ledger:Merge(by, time, keys)
	local diffs = self.data.diffs or {}
	local merging, keep = {}, {}
	local wanted
	if keys then
		wanted = {}
		for _, k in ipairs(keys) do wanted[k] = true end
	end
	for _, d in ipairs(diffs) do
		if not wanted or wanted[DiffKey(d)] then merging[#merging + 1] = d else keep[#keep + 1] = d end
	end
	-- The base is built from the merged changes alone, so it's the same on every officer that merges the same ones.
	self.data.diffs = merging
	if keep[1] then self:Rebuild() end
	self:Tidy(time)
	self:Stamp(time)
	local base = self.data.baseHead or { rev = 0, by = "" }
	self.data.baseHead = { rev = base.rev + #merging + 1, by = by }
	self.data.diffs = {}
	self.data.head.rev, self.data.head.by, self.data.head.hash = self.data.baseHead.rev, by, ""
	self.data.base = ns.PackTable(self)
	if keep[1] then
		self.data.diffs = keep
		self:Rebuild()
		self:UpdateHead()
	end
	return self.data.baseHead.rev
end

-- Keys (6.3) -----------------------------------------------------------------------------------------------------------

-- A new signing key: 32 bytes from the game's random numbers, mixed with the time and who made it.
function ns.NewKey(seed)
	local bytes = {}
	for i = 1, 32 do bytes[i] = string.char(math.random(0, 255)) end
	return ns.SHA256(table.concat(bytes) .. tostring(seed) .. tostring(GetServerTime()) .. tostring(GetTime()))
end

-- Signs every sub-row not signed with key `keyId`, using that key (design document 6.3).
function Ledger:Sign(keyId, key)
	local signer = ns.HMACSigner(key)
	for guid, subs in pairs(self.data.rows) do
		for raid, sub in pairs(subs) do
			if sub.key ~= keyId or not sub.sig then
				sub.key = keyId
				sub.sig = signer(ns.RowContent(guid, raid, sub)):sub(1, 8)
			end
		end
	end
end

-- Whether a sub-row's signature is good under the officers' keys (id -> key).
function ns.VerifyRow(keys, guid, raid, sub)
	local key = sub.key and keys[sub.key]
	if not key or type(sub.sig) ~= "string" then return false end
	return ns.HMACSHA256(key, ns.RowContent(guid, raid, sub)):sub(1, 8) == sub.sig
end

ns.Ledger = Ledger
