local _, ns = ...
local L = ns.L

-- Keeping officers' tables the same, and members' rows current (design document 6.3, 6.4). Only officers' word counts:
-- everything here is taken only from officers, except a member's answer about their own pity.
--
-- Between officers:
--   hello   {base, bh, digest, count, kid, kfp}  guild, or whisper in reply: where this officer's table stands
--   getbase {}                                   whisper: send me your base
--   base    {bytes, rev, by, merged}             whisper reply: the base table, and its recent merges (keys, hashes)
--   keys    {list, reply}                        whisper: the changes I hold; send me any I'm missing
--   diffs   {bytes}                              whisper: changes the other officer was missing
--   merge   {keys, time, by}                     guild: the writer merged these changes as the raid started
--   getkey  {force}                              whisper: send me the current signing key
--   key     {id, key, force}                     whisper reply
-- Officers to everyone:
--   diff    {bytes}                              guild: an officer's new change (members only take items' roles)
--   rows    {list, items, head}                  whisper: signed sub-rows for the player they belong to
-- Members:
--   getrows {}                                   whisper to an officer: a fresh install wants its rows
--   askpity {} / pity {list}                     whisper: anyone asking a player for their pity, and the answer
-- Anyone to the officers:
--   wonbefore {id, item, sid, writer, seen}      guild: a roll's winner had already won the item, by this client's log
--                                                or table (seen: {time, writer} of the win it saw, if it did)
--   getsub {raids} / sub {list}                  the writer asking a raider for sub-rows newer than its own (6.3)

local SYNC = ns.PREFIX_SYNC
local STALE = 60 -- seconds without an answer before a fetch is given up
local HELLO_DELAY = 5
local HELLO_INTERVAL = 30
local KEY_WAIT = 20 -- seconds an officer waits for another's key before making the first one
local MERGES_KEPT = 10 -- recent merges whose change keys are kept, so a late copy of a merged change is recognised
local SETTLE = 60 -- seconds after loading before the guild roster is trusted for officer changes
local RESYNC_CHECK_WAIT = 5 -- seconds after a resync before checking the new table against the log

local pull -- { from, last, replace }: a base being fetched
local pendingMerge
local reported = {}
local lastHello = {}
local readyAt

local function Me()
	return UnitGUID("player")
end

local function Ledger()
	return ns.ledger
end

local function Officer(sender)
	return ns.IsOfficer(sender)
end

-- Whether this client is fetching a base, so the writer shouldn't record anything yet.
function ns.SyncBusy()
	return pull ~= nil and GetTime() - pull.last < STALE
end

local function Short(bytes)
	return ns.ToHex(ns.SHA256(bytes or ""):sub(1, 8))
end

local function KeyFingerprint()
	local keys = ns.Keys()
	return keys.current and Short(keys[keys.current]) or ""
end

-- Merged changes ----------------------------------------------------------------------------------------------------

local function Merged()
	local data = Ledger().data
	data.merged = data.merged or {}
	return data.merged
end

local function WasMerged(key)
	for _, merge in ipairs(Merged()) do
		for _, k in ipairs(merge.keys) do
			if k == key then return true end
		end
	end
	return false
end

-- A merge, remembered with the base it started from and the one it made (by hash), and the changes it took in, so that
-- if another officer merged apart from this one, these can be applied again on top of theirs (UnsharedChanges).
local function NoteMerge(keys, time, from, fromRev, changes)
	local merged = Merged()
	merged[#merged + 1] = { time = time, keys = keys, from = from, fromRev = fromRev, to = Short(Ledger().data.base),
		changes = changes[1] and ns.EncodeDiffs(changes) or nil }
	while #merged > MERGES_KEPT do table.remove(merged, 1) end
end

-- The base a merge starts from (its hash and revision), and the changes it's about to take in.
local function Merging(keys)
	local w = Ledger()
	local want, changes = {}, {}
	for _, k in ipairs(keys) do want[k] = true end
	for _, change in ipairs(w.data.diffs or {}) do
		if want[ns.DiffKey(change)] then changes[#changes + 1] = change end
	end
	return Short(w.data.base), (w.data.baseHead or { rev = 0 }).rev, changes
end

-- Two officers who each merged while apart have bases that went separate ways. Taking the other's base, this officer
-- finds the last base they shared, from the merges each remembers, and keeps the changes it has merged since then that
-- the other hasn't, to apply again on top. Nil if their merges don't meet in what's remembered.
local function UnsharedChanges(theirs, theirBase)
	local newSince = { [theirBase] = #theirs + 1 } -- base hash -> the first of their merges made after it
	for i = #theirs, 1, -1 do
		local m = theirs[i]
		if type(m) == "table" then
			if type(m.to) == "string" and not newSince[m.to] then newSince[m.to] = i + 1 end
			if type(m.from) == "string" and not newSince[m.from] then newSince[m.from] = i end
		end
	end
	local mine = Merged()
	local hash, first = Short(Ledger().data.base), #mine + 1
	while not newSince[hash] do
		first = first - 1
		if first < 1 or mine[first].to ~= hash or not mine[first].from then return nil end
		hash = mine[first].from
	end
	local known = {}
	for i = newSince[hash], #theirs do
		for _, k in ipairs(type(theirs[i].keys) == "table" and theirs[i].keys or {}) do known[k] = true end
	end
	local list = {}
	for i = first, #mine do
		local changes = mine[i].changes and ns.Decode(ns.ReadDiffs, mine[i].changes)
		if mine[i].changes and not changes then return nil end
		for _, change in ipairs(changes or {}) do
			if not known[ns.DiffKey(change)] then list[#list + 1] = change end
		end
	end
	return list
end

-- Another officer's recent merges, taken on with their base: the changes are kept from this officer's own record of
-- any merge they share.
local function TakeMerged(theirs)
	local changes = {}
	for _, m in ipairs(Merged()) do
		if m.to then changes[m.to] = m.changes end
	end
	local list = {}
	for _, m in ipairs(type(theirs) == "table" and theirs or {}) do
		if type(m) == "table" and type(m.keys) == "table" then
			list[#list + 1] = { time = m.time, keys = m.keys, from = m.from, fromRev = m.fromRev, to = m.to,
				changes = m.to and changes[m.to] }
		end
	end
	Ledger().data.merged = list
end

-- Where this officer's table stands -----------------------------------------------------------------------------------

local function Summary()
	local w = Ledger()
	local keys = w:DiffKeys()
	local base = w.data.baseHead or { rev = 0 }
	return { base = base.rev, bh = Short(w.data.base), digest = Short(table.concat(keys, ",")), count = #keys,
		kid = ns.Keys().current or 0, kfp = KeyFingerprint() }
end

local function SayHello(target)
	if not Ledger() or not ns.HoldsTable() then return end
	lastHello[target or "GUILD"] = GetTime()
	ns.Send(SYNC, "hello", Summary(), target and "WHISPER" or "GUILD", target)
end
ns.SayHello = SayHello

local function Diverged(officer, rev)
	local key = officer .. ":" .. rev
	if reported[key] then return end
	reported[key] = true
	ns.Warn(L.WARN_DIVERGED:format(officer, rev, ns.ShortName(officer)))
end

local function SendKeys(target, reply)
	ns.Send(SYNC, "keys", { list = Ledger():DiffKeys(), reply = reply or nil }, "WHISPER", target)
end

local function FetchBase(officer, replace)
	pull = { from = officer, last = GetTime(), replace = replace }
	ns.Send(SYNC, "getbase", {}, "WHISPER", officer)
	ns.Fire("SYNC_CHANGED")
end

ns.Listen("LEDGER_READY", function()
	pull, pendingMerge, reported, lastHello = nil, nil, {}, {}
	readyAt = GetTime() + SETTLE
	if not Ledger() then return end
	-- Whether this client is an officer isn't known until the guild roster has loaded, so it's decided then.
	C_Timer.After(HELLO_DELAY, function()
		if not Ledger() then return end
		if ns.HoldsTable() then
			SayHello()
		elseif not Ledger().data.initialised and not IsInGroup() then
			-- A fresh install asks an officer for its rows (in a group, the writer's row check does it instead).
			local officer = ns.OnlineOfficers()[1]
			if officer and not ns.IsMe(officer.name) then ns.Send(SYNC, "getrows", {}, "WHISPER", officer.name) end
		end
	end)
	-- The first officer to need a key makes one, if no other officer has offered theirs by then.
	C_Timer.After(KEY_WAIT, function()
		if Ledger() and ns.HoldsTable() and not ns.Keys().current then
			ns.NewSigningKey()
			SayHello()
		end
	end)
end)

-- Replaces this officer's table with another officer's (/pl resync): their base, then their changes.
function ns.Resync(officer)
	local member = ns.GuildMember(officer)
	if not member or not ns.IsOfficer(member.name) then
		return ns.Print(L.MSG_NOT_OFFICER:format(officer or "?"))
	end
	ns.Print(L.MSG_FETCHING:format(member.name))
	FetchBase(member.name, true)
end

ns.Receive(SYNC, "hello", function(d, sender)
	local w = Ledger()
	if not w or not ns.HoldsTable() or not Officer(sender) or type(d) ~= "table" then return end
	if type(d.base) ~= "number" or type(d.bh) ~= "string" or type(d.digest) ~= "string" then return end
	local mine = Summary()
	-- Of two bases, the newer is taken, or for two officers who merged apart to the same revision, the higher hash;
	-- the officer taking it applies its own unshared changes again on top.
	if d.base > mine.base or (d.base == mine.base and d.bh > mine.bh) then
		if not ns.SyncBusy() and not reported[sender .. ":" .. d.base] then FetchBase(sender) end
	elseif d.base == mine.base and d.bh == mine.bh and d.digest ~= mine.digest then
		SendKeys(sender)
	end
	if type(d.kid) == "number" then
		if d.kid > mine.kid or (d.kid == mine.kid and d.kid > 0 and type(d.kfp) == "string" and d.kfp < mine.kfp) then
			ns.Send(SYNC, "getkey", { force = d.kid == mine.kid or nil }, "WHISPER", sender)
		end
	end
	-- An officer behind this one (or on a lower base at the same revision) hears where it stands, once in a while.
	local behind = d.base < mine.base or (d.base == mine.base and d.bh < mine.bh) or (type(d.kid) == "number" and d.kid < mine.kid)
	if behind and GetTime() - (lastHello[sender] or -HELLO_INTERVAL) > HELLO_INTERVAL then SayHello(sender) end
end)

ns.Receive(SYNC, "getbase", function(_, sender)
	local w = Ledger()
	if not w or not ns.HoldsTable() or not Officer(sender) then return end
	local base = w.data.baseHead or { rev = 0, by = "" }
	local merged = {}
	for i, m in ipairs(Merged()) do merged[i] = { time = m.time, keys = m.keys, from = m.from, fromRev = m.fromRev, to = m.to } end
	ns.Send(SYNC, "base", { bytes = w.data.base or "", rev = base.rev, by = base.by, merged = merged }, "WHISPER", sender)
end)

ns.Receive(SYNC, "base", function(d, sender)
	local w = Ledger()
	if not w or not pull or not ns.SameName(pull.from, sender) or type(d) ~= "table" then return end
	if type(d.bytes) ~= "string" or type(d.rev) ~= "number" then return end
	if d.bytes ~= "" and not ns.Decode(ns.ReadTable, d.bytes) then
		pull = nil
		ns.Fire("SYNC_CHANGED")
		return
	end
	local replace = pull.replace
	pull = nil
	local theirs = type(d.merged) == "table" and d.merged or {}
	local theirBase, last, first = Short(d.bytes ~= "" and d.bytes or nil), theirs[#theirs], theirs[1]
	local suspect = type(last) == "table" and last.to ~= theirBase
	local unshared = not replace and not suspect and UnsharedChanges(theirs, theirBase)
	if not replace and not unshared then
		-- A base the other officer's own last merge didn't make, or merges that don't meet (merged apart further back
		-- than either remembers): taking it could lose changes, so an officer decides, with /pl resync. An officer
		-- simply further behind than the other's remembered merges takes it.
		local rev = (w.data.baseHead or { rev = 0 }).rev
		local behind = not suspect and type(first) == "table" and type(first.fromRev) == "number" and rev < first.fromRev
		if not behind then
			Diverged(sender, d.rev)
			ns.Fire("SYNC_CHANGED")
			return
		end
	end
	TakeMerged(theirs)
	w.data.base = d.bytes ~= "" and d.bytes or nil
	w.data.baseHead = { rev = d.rev, by = type(d.by) == "string" and d.by or "" }
	local kept = {}
	if not replace then
		for _, change in ipairs(unshared or {}) do kept[#kept + 1] = change end
		for _, change in ipairs(w.data.diffs or {}) do
			if not WasMerged(ns.DiffKey(change)) then kept[#kept + 1] = change end
		end
	end
	w.data.diffs = kept
	w:Rebuild()
	w:UpdateHead()
	ns.SignRows()
	-- The changes merged into a base this officer took aren't in its log: /pl log checks from here on.
	ns.LogEvent({ kind = "base", from = ns.ShortName(sender), rev = d.rev })
	if replace then
		ns.Print(L.MSG_SYNCED:format(sender, w.data.head.rev))
		-- Once the other officer's newer changes are in too, what the old table had that this one doesn't.
		C_Timer.After(RESYNC_CHECK_WAIT, function()
			if ns.ReportLogCheck then ns.ReportLogCheck(ns.ShortName(sender)) end
		end)
	end
	ns.Fire("SYNC_CHANGED")
	ns.Fire("LEDGER_CHANGED")
	-- Then the changes since the base.
	SendKeys(sender)
end)

local function ChangesFor(keys)
	local want = {}
	for _, k in ipairs(keys) do want[k] = true end
	local list = {}
	for _, change in ipairs(Ledger().data.diffs or {}) do
		if not want[ns.DiffKey(change)] then list[#list + 1] = change end
	end
	return list
end

ns.Receive(SYNC, "keys", function(d, sender)
	local w = Ledger()
	if not w or not ns.HoldsTable() or not Officer(sender) or type(d) ~= "table" or type(d.list) ~= "table" then return end
	local theirs = {}
	for _, k in ipairs(d.list) do
		if type(k) == "string" then theirs[#theirs + 1] = k end
	end
	local missing = ChangesFor(theirs)
	if missing[1] then ns.Send(SYNC, "diffs", { bytes = ns.EncodeDiffs(missing) }, "WHISPER", sender) end
	if not d.reply then
		local lacking = false
		for _, k in ipairs(theirs) do
			if not w:HasDiff(k) and not WasMerged(k) then lacking = true end
		end
		if lacking then SendKeys(sender, true) end
	end
end)

-- A pending merge waits until every change it names is here.
local function TryMerge()
	local w = Ledger()
	if not pendingMerge or not w then return end
	for _, k in ipairs(pendingMerge.keys) do
		if not w:HasDiff(k) and not WasMerged(k) then return end
	end
	local merge = pendingMerge
	pendingMerge = nil
	local keys = {}
	for _, k in ipairs(merge.keys) do
		if w:HasDiff(k) then keys[#keys + 1] = k end
	end
	local from, fromRev, changes = Merging(keys)
	w:Merge(merge.by, merge.time, keys)
	NoteMerge(merge.keys, merge.time, from, fromRev, changes)
	ns.SignRows()
	ns.LogEvent({ kind = "merge", rev = w.data.head.rev, by = merge.by, changes = #merge.keys })
	ns.Fire("LEDGER_CHANGED")
end

local function TakeChanges(bytes)
	local changes = type(bytes) == "string" and ns.Decode(ns.ReadDiffs, bytes)
	if not changes then return end
	for _, change in ipairs(changes) do
		if not WasMerged(ns.DiffKey(change)) then ns.TakeChange(change) end
	end
	TryMerge()
end

ns.Receive(SYNC, "diffs", function(d, sender)
	if ns.HoldsTable() and Officer(sender) and type(d) == "table" then TakeChanges(d.bytes) end
end)

-- A new change from an officer: officers take it whole; members only keep items' roles, which they show (4.6).
ns.Receive(SYNC, "diff", function(d, sender)
	local w = Ledger()
	if not w or not Officer(sender) or type(d) ~= "table" then return end
	if ns.HoldsTable() then return TakeChanges(d.bytes) end
	local changes = type(d.bytes) == "string" and ns.Decode(ns.ReadDiffs, d.bytes)
	for _, change in ipairs(changes or {}) do
		if change.op == "itemroles" then
			w:SetItemRoles(change.item, change.roles)
			ns.Fire("LEDGER_CHANGED")
		end
	end
end)

-- Shares a change this officer made: to every officer (and members, who take items' roles), and the new signed
-- sub-rows to any player it changed, if they're online.
function ns.ShareChange(change, stamped)
	ns.Send(SYNC, "diff", { bytes = ns.EncodeDiffs({ change }) }, "GUILD")
	local players = {}
	for _, at in ipairs(stamped or {}) do players[at[1]] = true end
	for guid in pairs(players) do
		if guid ~= Me() then ns.SendRows(guid) end
	end
end

-- Merging, as a raid starts (6.4) --------------------------------------------------------------------------------------

-- The writer merges every change it holds into a new base, and tells the other officers which.
function ns.MergeChanges()
	local w = Ledger()
	if not w or not ns.HoldsTable() or ns.SyncBusy() then return end
	local keys = w:DiffKeys()
	if not keys[1] then return end
	local time = GetServerTime()
	local from, fromRev, changes = Merging(keys)
	w:Merge(Me(), time, keys)
	NoteMerge(keys, time, from, fromRev, changes)
	ns.SignRows()
	ns.LogEvent({ kind = "merge", rev = w.data.head.rev, by = Me(), changes = #keys })
	ns.Send(SYNC, "merge", { keys = keys, time = time, by = Me() }, "GUILD")
	ns.Fire("LEDGER_CHANGED")
end

ns.Receive(SYNC, "merge", function(d, sender)
	local w = Ledger()
	if not w or not ns.HoldsTable() or not Officer(sender) or type(d) ~= "table" then return end
	if type(d.keys) ~= "table" or type(d.time) ~= "number" or type(d.by) ~= "string" then return end
	pendingMerge = { keys = d.keys, time = d.time, by = d.by }
	TryMerge()
	if pendingMerge then SendKeys(sender) end -- missing some: ask for them, and merge when they're here
end)

-- Keys (6.3) ----------------------------------------------------------------------------------------------------------

ns.Receive(SYNC, "getkey", function(d, sender)
	local keys = ns.Keys()
	if not ns.HoldsTable() or not Officer(sender) or not keys.current then return end
	ns.Send(SYNC, "key", { id = keys.current, key = keys[keys.current], force = type(d) == "table" and d.force or nil },
		"WHISPER", sender)
end)

ns.Receive(SYNC, "key", function(d, sender)
	if not ns.HoldsTable() or not Officer(sender) or type(d) ~= "table" then return end
	if type(d.id) ~= "number" or type(d.key) ~= "string" or #d.key ~= 32 then return end
	local keys = ns.Keys()
	if d.force and keys[d.id] and keys[d.id] ~= d.key then keys[d.id] = nil end
	if ns.AddKey(d.id, d.key) then
		ns.SignRows()
		ns.Fire("LEDGER_CHANGED")
	end
end)

-- When an officer is demoted or leaves the guild, the first officer online makes a new key and the rest fetch it.
local function CheckOfficers()
	local w = Ledger()
	if not w or not ns.HoldsTable() or ns.IsTestMode() or not readyAt or GetTime() < readyAt then return end
	if GetNumGuildMembers() == 0 then return end
	local now = {}
	for _, officer in ipairs(ns.GuildOfficers and ns.GuildOfficers() or {}) do now[officer.guid] = true end
	local known = w.data.officers
	w.data.officers = now
	if not known then return end
	for guid in pairs(known) do
		if not now[guid] then
			local first = ns.OnlineOfficers()[1]
			if first and ns.IsMe(first.name) then
				ns.NewSigningKey()
				SayHello()
			end
			return
		end
	end
end
ns.On("GUILD_ROSTER_UPDATE", CheckOfficers)

-- Members' rows (6.3) -------------------------------------------------------------------------------------------------

-- Sends a player their signed sub-rows (all of them, or those for `raids`), with the item table for those raids.
function ns.SendRows(guid, raids)
	local w = Ledger()
	local member = ns.GroupMember(guid) or ns.GuildMember(guid)
	if not w or not ns.HoldsTable() or not member or not member.name then return end
	local list, only = {}, {}
	for raid, sub in pairs(ns.LiveRows(guid)) do
		if not raids or raids[raid] then
			list[#list + 1] = ns.EncodeRow(guid, raid, sub)
			only[raid] = true
		end
	end
	if raids then
		for raid in pairs(raids) do
			if not only[raid] then list[#list + 1] = ns.EncodeRow(guid, raid, { version = GetServerTime(), cells = {} }) end
		end
	end
	local head = w.data.head
	ns.Send(SYNC, "rows", { list = list, items = ns.EncodeItems(w.data.items, only), head = { rev = head.rev, by = head.by } },
		"WHISPER", member.name)
end

ns.Receive(SYNC, "rows", function(d, sender)
	local w = Ledger()
	if not w or not Officer(sender) or type(d) ~= "table" or type(d.list) ~= "table" then return end
	local me = Me()
	local changed = {}
	for _, bytes in ipairs(d.list) do
		local guid, raid, sub = ns.Decode(ns.ReadRow, type(bytes) == "string" and bytes or "")
		if guid == me and not ns.HoldsTable() then
			-- What it changes goes in the full log, so /pl log can check the row against it.
			local old = ns.RowsOf(me)[raid]
			for item, cell in pairs(sub.cells) do
				if not old or old.cells[item] ~= cell then changed[item] = cell end
			end
			for item in pairs(old and old.cells or {}) do
				if sub.cells[item] == nil then changed[item] = false end
			end
			ns.TakeRow(guid, raid, sub)
		end
	end
	if next(changed) then ns.LogEvent({ kind = "row", officer = ns.ShortName(sender), cells = changed }) end
	local items = type(d.items) == "string" and ns.Decode(ns.ReadItems, d.items)
	if items and not ns.HoldsTable() then
		for _, raid in ipairs(items.raids) do
			for _, boss in ipairs(raid.bosses) do
				for _, item in ipairs(boss.items) do
					w:Learn(item, raid.name ~= "" and raid.name or nil, boss.name ~= "" and boss.name or nil)
					if items.roles[item] then w:SetItemRoles(item, items.roles[item]) end
				end
			end
		end
	end
	if type(d.head) == "table" and type(d.head.rev) == "number" and not ns.HoldsTable() then
		w.data.head.rev, w.data.head.by = d.head.rev, type(d.head.by) == "string" and d.head.by or ""
	end
	w.data.initialised = true
	ns.Fire("LEDGER_CHANGED")
end)

ns.Receive(SYNC, "getrows", function(_, sender)
	local member = ns.GuildMember(sender)
	if member and member.guid and ns.HoldsTable() then ns.SendRows(member.guid) end
end)

-- The row check (6.3): a raider's client says what it holds when it joins a group or a new writer takes over. The
-- writer sends back any sub-row that differs; and a sub-row newer than its own, it asks for, to take on (a raid it
-- wasn't at, signed by the officers who were).
function ns.CheckRows(guid, bytes)
	local w = Ledger()
	if not w or not ns.HoldsTable() or type(bytes) ~= "string" then return end
	local checks = ns.Decode(ns.ReadRowCheck, bytes)
	if not checks then return end
	local mine = ns.LiveRows(guid)
	local resend, newer, seen = {}, {}, {}
	for _, check in ipairs(checks) do
		seen[check.raid] = true
		local sub = mine[check.raid]
		if not sub or check.version > (sub.version or 0) then
			newer[#newer + 1] = check.raid
		elseif ns.RowHash(guid, check.raid, sub) ~= check.hash then
			resend[check.raid] = true
		end
	end
	for raid in pairs(mine) do
		if not seen[raid] then resend[raid] = true end
	end
	if next(resend) or not checks[1] then ns.SendRows(guid, next(resend) and resend or nil) end
	local member = ns.GroupMember(guid)
	if newer[1] and member then ns.Send(SYNC, "getsub", { raids = newer }, "WHISPER", member.name) end
end

ns.Receive(SYNC, "getsub", function(d, sender)
	if not Officer(sender) or type(d) ~= "table" or type(d.raids) ~= "table" then return end
	local me, list = Me(), {}
	local rows = ns.RowsOf(me)
	for _, raid in ipairs(d.raids) do
		if type(raid) == "string" and rows[raid] then list[#list + 1] = ns.EncodeRow(me, raid, rows[raid]) end
	end
	if list[1] then ns.Send(SYNC, "sub", { list = list }, "WHISPER", sender) end
end)

ns.Receive(SYNC, "sub", function(d, sender)
	local member = ns.GroupMember(sender)
	if not member or not ns.HoldsTable() or type(d) ~= "table" or type(d.list) ~= "table" then return end
	for _, bytes in ipairs(d.list) do
		local guid, raid, sub = ns.Decode(ns.ReadRow, type(bytes) == "string" and bytes or "")
		if guid == member.guid then ns.Adopt(guid, raid, sub) end
	end
end)

-- Anyone's pity, just for interest (/pl pity <name>): asked of their own addon, and not checked.
local asking = {}
function ns.AskPity(name)
	asking[ns.ShortName(name)] = true
	ns.Send(SYNC, "askpity", {}, "WHISPER", name)
end

-- Raiders checking a roll's winners (6.3) ------------------------------------------------------------------------------

local REPORT_WAIT = 3 -- seconds an officer's client gathers reports on the same win before warning
local reportedWins, winReports = {}, {}

-- Names for a warning: the first few, then how many more.
local function NameList(names)
	if #names <= 3 then return table.concat(names, ", ") end
	return L.LIST_MORE:format(table.concat(names, ", ", 1, 3), #names - 3)
end

-- A report reaching an officer: reports on the same win are gathered for a few seconds, then shown as one warning
-- naming everyone who sent one; later ones make another. An officer who saw the lockout lifted since lets it go.
local function TakeReport(d, reporter)
	if not ns.HoldsTable() then return end
	local unlocked = ns.LoggedUnlock(d.id, d.item)
	if unlocked and type(d.seen) == "table" and unlocked > (tonumber(d.seen.time) or 0) then return end
	local key = d.sid .. ":" .. d.id
	local entry = winReports[key]
	if not entry then
		entry = { names = {}, heard = {}, d = d }
		winReports[key] = entry
	end
	if entry.heard[reporter] then return end
	entry.heard[reporter] = true
	entry.names[#entry.names + 1] = reporter
	if entry.timer then return end
	entry.timer = C_Timer.NewTimer(REPORT_WAIT, function()
		entry.timer = nil
		local names, first = entry.names, entry.d
		entry.names = {}
		ns.LogEvent({ kind = "wonbefore", id = first.id, item = first.item, sid = first.sid, reporters = names, seen = first.seen })
		local text = L.WARN_WON_BEFORE:format(NameList(names), ns.NameOf(first.id) or first.id, ns.ItemLink(first.item),
			first.writer or "?")
		if type(first.seen) == "table" and first.seen.writer then
			text = text .. " " .. L.WARN_WON_BEFORE_SEEN:format(first.seen.writer, date("%d %b", tonumber(first.seen.time) or 0))
		end
		ns.Warn(text)
	end)
end

-- When a roll is decided, before it's awarded, every client checks each winner against its own full log (every roll
-- it watched) and, on an officer's client, its table: one lookup each. A winner who had already won the item is
-- reported to the officers, who work out the truth (the report isn't proof: the reporter's addon could be tampered
-- with). The writer's table can't know, or it wouldn't have counted the roll, but its log can.
function ns.ReportWins(m, writer)
	if m.greed or not ns.guild then return end
	for _, id in ipairs(m.winners or {}) do
		local key = m.sid .. ":" .. id
		local seen = ns.LoggedWin(id, m.item)
		if seen and seen.sid == m.sid then seen = nil end
		if not reportedWins[key] and (seen or ns.HasWon(id, m.item)) then
			reportedWins[key] = true
			local report = { id = id, item = m.item, sid = m.sid, writer = writer,
				seen = seen and { time = seen.time, writer = seen.writer } or nil }
			ns.Send(SYNC, "wonbefore", report, "GUILD")
			TakeReport(report, ns.PlayerName()) -- a client doesn't hear its own guild messages
		end
	end
end

ns.Receive(SYNC, "wonbefore", function(d, sender)
	if type(d) ~= "table" or type(d.id) ~= "string" or type(d.item) ~= "number" or type(d.sid) ~= "string" then return end
	if d.writer ~= nil and type(d.writer) ~= "string" then return end
	TakeReport(d, ns.ShortName(sender))
end)

ns.Receive(SYNC, "askpity", function(_, sender)
	local me, list = Me(), {}
	for raid, sub in pairs(ns.RowsOf(me)) do list[#list + 1] = ns.EncodeRow(me, raid, sub) end
	ns.Send(SYNC, "pity", { list = list }, "WHISPER", sender)
end)

ns.Receive(SYNC, "pity", function(d, sender)
	if not asking[ns.ShortName(sender)] or type(d) ~= "table" or type(d.list) ~= "table" then return end
	asking[ns.ShortName(sender)] = nil
	local rows = {}
	for _, bytes in ipairs(d.list) do
		local _, raid, sub = ns.Decode(ns.ReadRow, type(bytes) == "string" and bytes or "")
		if raid then rows[raid] = sub end
	end
	if ns.ShowPityOf then ns.ShowPityOf(sender, rows) end
end)
