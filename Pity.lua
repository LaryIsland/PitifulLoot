local _, ns = ...

-- The ledger in use (design document 6): on an officer's client, the guild's whole table (the last merged base
-- and the changes since, Ledger.lua); on a member's, their own row. Changes are made here and shared by Sync.lua.
-- Every client also keeps its own full log of what it saw, never shared (6.1).

local KEYS_KEPT = 3 -- signing keys kept, the current one and those before it (6.3)

local function Me()
	return UnitGUID("player")
end

-- Officers hold the whole table; members their own row.
function ns.HoldsTable()
	return ns.IsOfficer(ns.PlayerName())
end

-- The ledger for a guild, from saved variables (an empty one the first time). It's saved as `ledger`, never `ledgers`,
-- which held the old shared ledger, so data in that layout is never read as this.
function ns.LoadLedger(guild)
	ns.saved.ledger = ns.saved.ledger or {}
	ns.saved.ledger[guild] = ns.saved.ledger[guild] or {}
	return ns.NewLedger(ns.saved.ledger[guild])
end

-- Sub-rows taken on from raiders (6.3) --------------------------------------------------------------------------------

-- On the writer's client, sub-rows a raider showed that are newer than its own table's, signed by the officers of a
-- raid this writer's officers haven't heard from yet (guid -> raid -> sub-row). Used for this group only: never
-- saved or merged, as that raid's own changes will arrive in time, and dropped once the table has caught up.
local adopted = {}

-- Takes on a raider's sub-row if it's newer than the table's and the officers' key signed it.
function ns.Adopt(guid, raid, sub)
	if not ns.ledger or not ns.HoldsTable() or type(sub) ~= "table" then return false end
	local own = ns.ledger.data.rows[guid] and ns.ledger.data.rows[guid][raid]
	if own and (own.version or 0) >= sub.version then return false end
	if not ns.VerifyRow(ns.Keys(), guid, raid, sub) then return false end
	adopted[guid] = adopted[guid] or {}
	adopted[guid][raid] = sub
	ns.Fire("LEDGER_CHANGED")
	return true
end

-- A player's sub-rows as they stand: the table's, with any newer one taken on in their place.
function ns.LiveRows(guid)
	local own = ns.ledger and ns.ledger.data.rows[guid] or {}
	local taken = adopted[guid]
	if not taken then return own end
	local rows = {}
	for raid, sub in pairs(own) do rows[raid] = sub end
	for raid, sub in pairs(taken) do
		if own[raid] and (own[raid].version or 0) >= sub.version then
			taken[raid] = nil -- the table has caught up
		else
			rows[raid] = sub
		end
	end
	if next(taken) == nil then adopted[guid] = nil end
	return rows
end

-- A roll's result on sub-rows taken on: applied the same way, stamped and signed, so the raider's own copy matches.
local function ResultOnTaken(change)
	local won = {}
	for _, id in ipairs(change.winners) do won[id] = true end
	local keys, done = ns.Keys(), {}
	local function Apply(id)
		-- The taken-on sub-row holding the item, or else the one for the item's raid: as the raider's officers filed it,
		-- which needn't match this table.
		local raid, sub
		for r, s in pairs(adopted[id] or {}) do
			if s.cells[change.item] then raid, sub = r, s end
		end
		if not sub then
			raid = ns.ledger:RaidOf(change.item)
			sub = adopted[id] and adopted[id][raid]
		end
		if not sub or change.time <= sub.version then return end
		local cell = sub.cells[change.item]
		if won[id] then
			sub.cells[change.item] = ns.CELL_WON
		elseif cell ~= ns.CELL_WON then
			sub.cells[change.item] = cell and math.min(cell + 1, 4) or 0
		end
		sub.version, sub.key, sub.sig = change.time, nil, nil
		if keys.current then
			sub.key = keys.current
			sub.sig = ns.HMACSHA256(keys[keys.current], ns.RowContent(id, raid, sub)):sub(1, 8)
		end
		done[#done + 1] = { id, raid }
	end
	for _, id in ipairs(change.losers) do Apply(id) end
	for _, id in ipairs(change.winners) do Apply(id) end
	return done
end

function ns.ForgetTaken()
	adopted = {}
end

-- Reading -------------------------------------------------------------------------------------------------------------

-- A player's sub-row holding an item's cell, as it stands: the one for the item's raid, or (on a member's client,
-- whose item table can differ from the officers') whichever of their sub-rows has it.
local function SubFor(guid, item)
	if not ns.ledger then return nil end
	local rows = ns.LiveRows(guid)
	-- A taken-on sub-row is newer than the table's by definition, wherever either files the item.
	for _, taken in pairs(adopted[guid] or {}) do
		if taken.cells[item] then return taken end
	end
	local sub = rows[ns.ledger:RaidOf(item)]
	if sub and sub.cells[item] then return sub end
	for _, other in pairs(rows) do
		if other.cells[item] then return other end
	end
	return sub
end

-- A player's pity on an item now, with any leaver decay (0 to 50). A member's client only knows their own; others'
-- come with each roll (Session.lua).
function ns.PityOf(guid, item)
	if not ns.ledger then return 0 end
	local sub = SubFor(guid, item)
	-- A sub-row taken on from a raider counts as it is (it may be filed under a raid this table doesn't know yet).
	for _, taken in pairs(sub and adopted[guid] or {}) do
		if taken == sub then
			local cell = sub.cells[item]
			return cell and cell ~= ns.CELL_WON and (cell + 1) * ns.PITY_STEP or 0
		end
	end
	return (ns.ledger:Pity(guid, item, GetServerTime()))
end

function ns.HasWon(guid, item)
	local sub = SubFor(guid, item)
	return sub ~= nil and sub.cells[item] == ns.CELL_WON
end

-- A player's sub-rows (raid -> sub-row), or an empty table.
function ns.RowsOf(guid)
	return ns.ledger and ns.ledger.data.rows[guid] or {}
end

-- The revision and who made it (a GUID), for the footer and /pl status: the table's own on an officer's client, the
-- latest an officer has said on a member's.
function ns.Head()
	return ns.ledger and ns.ledger.data.head
end

-- Signing (6.3) -----------------------------------------------------------------------------------------------------

-- The officers' keys (id -> key, and `current`), kept with the table on officers' clients.
function ns.Keys()
	local data = ns.ledger and ns.ledger.data
	if not data then return {} end
	data.keys = data.keys or {}
	return data.keys
end

-- Adds a key; the newest becomes the current one, and only the last few are kept.
function ns.AddKey(id, key)
	local keys = ns.Keys()
	if keys[id] then return false end
	keys[id] = key
	if not keys.current or id > keys.current then keys.current = id end
	for old in pairs(keys) do
		if type(old) == "number" and old <= keys.current - KEYS_KEPT then keys[old] = nil end
	end
	ns.SignRows()
	return true
end

-- Makes a new key, one higher than any held: the first officer to need one, or after an officer is removed (6.3).
function ns.NewSigningKey()
	local keys = ns.Keys()
	local id = (keys.current or 0) + 1
	ns.AddKey(id, ns.NewKey(Me()))
	return id
end

-- Signs every sub-row not signed with the current key.
function ns.SignRows()
	local keys = ns.Keys()
	if keys.current and ns.ledger and ns.HoldsTable() then ns.ledger:Sign(keys.current, keys[keys.current]) end
end

-- Changes (6.4) -------------------------------------------------------------------------------------------------------

local lastTime, lastN = 0, 0

-- A new change by this officer, stamped with the time, a sequence number for changes in the same second, and who.
function ns.NewChange(change)
	local now = GetServerTime()
	if now == lastTime then lastN = lastN + 1 else lastTime, lastN = now, 0 end
	change.time, change.n, change.by = change.time or now, lastN, Me()
	return change
end

-- Records a change on this officer's table and shares it. Returns whether it was taken, and why not if not.
function ns.RecordChange(change)
	if not ns.ledger then return false, ns.L.LEDGER_NO_GUILD end
	if not ns.HoldsTable() then return false, ns.L.LEDGER_NOT_OFFICER end
	if ns.SyncBusy() then return false, ns.L.LEDGER_SYNCING end
	local _, stamped = ns.ledger:AddDiff(change)
	ns.Capture("change", change)
	ns.SignRows()
	ns.LogEvent({ kind = "change", change = ns.Copy(change) })
	ns.Fire("LEDGER_CHANGED")
	if ns.ShareChange then ns.ShareChange(change, stamped) end
	return true
end

-- A change from another officer (Sync.lua): applied, signed, logged. Returns whether it was new.
function ns.TakeChange(change)
	if not ns.ledger or not ns.HoldsTable() then return false end
	local new = ns.ledger:AddDiff(change)
	if new then
		ns.SignRows()
		if change.op == "result" then ResultOnTaken(change) end
		-- A result for the roll this client watched is already in the log, as the roll itself.
		if not (change.op == "result" and ns.WatchedRoll and ns.WatchedRoll(change)) then
			ns.LogEvent({ kind = "change", change = ns.Copy(change) })
		end
		ns.Fire("LEDGER_CHANGED")
	end
	return new
end

-- Double wins (6.3): a player who won an item in a raid whose writer didn't know they'd already won it there (no
-- addon, a client that missed or lost the award, or a tampered one). Every officer's full log notes each once; the
-- officers who recorded either win are warned, as they ran those rolls.
function ns.CheckDoubleWins()
	local w = ns.ledger
	if not w or not ns.HoldsTable() or not w.doubles[1] then return end
	local doubles = w.doubles
	w.doubles = {}
	w.data.flagged = w.data.flagged or {}
	local me = Me()
	for _, double in ipairs(doubles) do
		local key = ns.DiffKey(double.change) .. ":" .. double.id
		if not w.data.flagged[key] then
			w.data.flagged[key] = true
			ns.LogEvent({ kind = "doublewin", id = double.id, item = double.item, change = ns.DiffKey(double.change),
				first = double.first and ns.DiffKey(double.first) or nil })
			if double.change.by == me or (double.first and double.first.by == me) then
				ns.Warn(ns.L.WARN_DOUBLE_WIN:format(ns.NameOf(double.id) or double.id, ns.ItemLink(double.item),
					ns.NameOf(double.change.by) or double.change.by))
			end
		end
	end
end
ns.Listen("LEDGER_CHANGED", ns.CheckDoubleWins)

-- A roll's result (5.1): the writer records it as a change and returns the change and the new signatures of the
-- sub-rows it changed ({ guid, raid, version, key, sig }), which go with the message saying it was awarded.
function ns.RecordResult(item, raid, boss, losers, winners)
	local change = ns.NewChange({ op = "result", item = item, raid = raid or "", boss = boss or "", losers = losers, winners = winners })
	if not ns.ledger or not ns.HoldsTable() then return nil end
	local _, stamped = ns.ledger:AddDiff(change)
	ns.Capture("change", change)
	ns.SignRows()
	-- The signatures go with the award: for a raider whose sub-row was taken on, that one alone (it's their real row);
	-- for everyone else, the table's.
	local taken = ResultOnTaken(change)
	local sigs, viaTaken = {}, {}
	for _, at in ipairs(taken) do
		viaTaken[at[1]] = true
		local sub = adopted[at[1]][at[2]]
		sigs[#sigs + 1] = { at[1], at[2], sub.version, sub.key, sub.sig }
	end
	for _, at in ipairs(stamped or {}) do
		local sub = not viaTaken[at[1]] and ns.ledger.data.rows[at[1]] and ns.ledger.data.rows[at[1]][at[2]]
		if sub then sigs[#sigs + 1] = { at[1], at[2], sub.version, sub.key, sub.sig } end
	end
	ns.Fire("LEDGER_CHANGED") -- the writer's log has the roll itself (Session.lua)
	if ns.ShareChange then ns.ShareChange(change) end
	return change, sigs
end

-- The writer's result reaching another client (Session.lua): an officer adds the change; a member applies their own
-- share to their row and takes its new signature.
function ns.TakeResult(change, sigs, head)
	if not ns.ledger then return end
	if ns.HoldsTable() then
		ns.TakeChange(change)
	else
		local me = Me()
		local w = ns.ledger
		w:ApplyDiff(change, me)
		for _, s in ipairs(sigs or {}) do
			if s[1] == me and type(s[2]) == "string" then
				-- The cell goes in the sub-row the writer filed it under, whatever this client's own item table says.
				local raid, moving = s[2], {}
				for other, sub in pairs(w.data.rows[me] or {}) do
					if other ~= raid and sub.cells[change.item] then moving[other] = sub.cells[change.item] end
				end
				for other, cell in pairs(moving) do
					w:Store(me, other, change.item, nil)
					w:Store(me, raid, change.item, cell)
				end
				w.changed = {}
				local sub = w.data.rows[me] and w.data.rows[me][raid]
				if sub then
					sub.version = change.time
					if s[3] == change.time then sub.key, sub.sig = s[4], s[5] end
				end
			end
		end
		if type(head) == "table" and type(head.rev) == "number" then
			ns.ledger.data.head.rev, ns.ledger.data.head.by = head.rev, head.by
		end
		ns.Fire("LEDGER_CHANGED")
	end
end

-- Takes a signed sub-row from an officer (a member's own, or an officer catching up): kept as it is.
function ns.TakeRow(guid, raid, sub)
	if not ns.ledger then return end
	local rows = ns.ledger.data.rows
	rows[guid] = rows[guid] or {}
	if next(sub.cells) == nil then
		rows[guid][raid] = nil
		if next(rows[guid]) == nil then rows[guid] = nil end
	else
		rows[guid][raid] = sub
	end
	for item in pairs(sub.cells) do
		if not ns.ledger.where[item] then ns.ledger:Learn(item, raid ~= "" and raid or nil) end
	end
	ns.Fire("LEDGER_CHANGED")
end

-- Where an item drops, learned from what this client sees (5.2, 6.1): a member's own item table; an officer's comes
-- from the changes, so every officer's is the same.
function ns.LearnSource(item, raid, boss)
	if ns.ledger and not ns.HoldsTable() then ns.ledger:Learn(item, raid, boss) end
end

-- The full log (6.1) ------------------------------------------------------------------------------------------------

-- Everything this client saw, for checking and rolling back later; never shared. Saved as:
--   players  { { guid, name }... }   every player the log mentions, once: packed events refer to them by place
--   chunks   { "<packed>"... }       50 events at a time, compacted (below), serialised, deflated and base64'd; the
--                                    oldest chunk goes once there are more than 20
--   open     { event... }            the newest events, until there are 50 to pack
--   tail     "<packed>"              at logout, the open events packed too, unpacked again when the log's next used
--   wins     { win... }              the last 100 need wins and lifted lockouts seen, for checking a roll's winners;
--                                    packed at logout too (packedWins), with players by place
-- In a chunk, each event's time is the gap since the one before (the first's is its own), rolls and results are
-- lists in a fixed order rather than named fields, and an entrant is one number. Events that don't fit are kept as
-- they are, with GUIDs as places.
local LOG_CHUNK, LOG_CHUNKS = 50, 20
local WINS_KEPT = 100
local DEFLATE = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
local AWARD, CHANGE = 1, 2
local AWARD_FIELDS = { kind = true, time = true, sid = true, item = true, copies = true, greed = true, instance = true,
	boss = true, writer = true, entrants = true, rounds = true, winners = true }
local ENTRANT_FIELDS = { name = true, pity = true, offSpec = true, unknownRole = true }

local current -- the log the lookups below were built for
local latest = {} -- "guid:item" -> the newest entry in wins for it
local placeMaps = setmetatable({}, { __mode = "k" }) -- log -> guid -> place in its players

local function Key(guid, item)
	return guid .. ":" .. tostring(item)
end

local function Only(t, allowed)
	for k in pairs(t) do
		if not allowed[k] then return false end
	end
	return true
end

-- Players by place (and back), with each GUID's latest name.
local function Place(log, guid, name)
	if type(guid) ~= "string" then return guid end
	local places = placeMaps[log]
	if not places then
		places = {}
		for place, player in ipairs(log.players) do places[player[1]] = place end
		placeMaps[log] = places
	end
	local place = places[guid]
	if not place then
		place = #log.players + 1
		log.players[place] = { guid }
		places[guid] = place
	end
	if name then log.players[place][2] = name end
	return place
end

local function Guid(log, place)
	local player = log.players[place]
	return player and player[1] or place
end

local function Places(log, list)
	local out = {}
	for i, guid in ipairs(list or {}) do out[i] = Place(log, guid) end
	return out
end

local function Guids(log, list)
	local out = {}
	for i, place in ipairs(list or {}) do out[i] = Guid(log, place) end
	return out
end

-- An entrant as one number: pity in tens, plus 8 if off-spec and 16 if their role was unknown. Nil if it doesn't fit.
local function EntrantCode(entrant)
	local pity = entrant.pity
	if type(pity) ~= "number" or pity % 10 ~= 0 or pity < 0 or pity > 50 or not Only(entrant, ENTRANT_FIELDS) then return nil end
	if (entrant.offSpec ~= nil and entrant.offSpec ~= true) or (entrant.unknownRole ~= nil and entrant.unknownRole ~= true) then
		return nil
	end
	return pity / 10 + (entrant.offSpec and 8 or 0) + (entrant.unknownRole and 16 or 0)
end

local function EntrantFrom(code, name)
	return { name = name, pity = code % 8 * 10, offSpec = code % 16 >= 8 or nil, unknownRole = code >= 16 or nil }
end

-- A roll's id ("writer:opened:count") as its count, how long before the event it opened, and its writer if that isn't
-- the event's (the roll changed hands); or whole if it isn't one.
local function SidPacked(sid, writer, time)
	local by, opened, count = tostring(sid):match("^(.*):(%-?%d+):(%d+)$")
	if type(sid) ~= "string" or not by then return sid end
	return { tonumber(count), time - tonumber(opened), by ~= writer and by or false }
end

local function SidFrom(packed, writer, time)
	if type(packed) ~= "table" then return packed end
	return ("%s:%d:%d"):format(packed[3] or writer, time - packed[2], packed[1])
end

local function False(v)
	if v == nil then return false end
	return v
end

local function Nil(v)
	if v == false then return nil end
	return v
end

-- An event as it's kept in a chunk, `gap` being its time less the one before's.
local function Compact(log, event, gap)
	if event.kind == "award" and Only(event, AWARD_FIELDS) and type(event.entrants) == "table" then
		local entrants = {}
		for guid, entrant in pairs(event.entrants) do
			local code = EntrantCode(entrant)
			if not code then entrants = nil break end
			entrants[Place(log, guid, entrant.name)] = code
		end
		if entrants then
			local rounds = {}
			for i, round in ipairs(event.rounds or {}) do
				rounds[i] = {}
				for guid, roll in pairs(round) do rounds[i][Place(log, guid)] = roll end
			end
			return { AWARD, gap, SidPacked(event.sid, event.writer, event.time), event.item, event.copies,
				False(event.instance), False(event.boss), False(event.writer), entrants, rounds, Places(log, event.winners),
				False(event.greed) }
		end
	end
	if event.kind == "change" and type(event.change) == "table" and Only(event, { kind = true, time = true, change = true }) then
		local c = ns.Copy(event.change)
		c.id, c.by = Place(log, c.id), Place(log, c.by)
		if c.losers then c.losers = Places(log, c.losers) end
		if c.winners then c.winners = Places(log, c.winners) end
		if type(c.time) == "number" then c.time = event.time - c.time end
		return { CHANGE, gap, c }
	end
	-- Anything else as it is, with its time as the gap and GUIDs as places.
	local e = ns.Copy(event)
	e.time = gap
	if e.id then e.id = Place(log, e.id) end
	if e.by then e.by = Place(log, e.by) end
	return e
end

local function Expand(log, e, time)
	if e[1] == AWARD then
		local writer = Nil(e[8])
		local entrants = {}
		for place, code in pairs(e[9]) do entrants[Guid(log, place)] = EntrantFrom(code, log.players[place] and log.players[place][2]) end
		local rounds = {}
		for i, round in ipairs(e[10]) do
			rounds[i] = {}
			for place, roll in pairs(round) do rounds[i][Guid(log, place)] = roll end
		end
		return { kind = "award", time = time, sid = SidFrom(e[3], writer, time), item = e[4], copies = e[5],
			instance = Nil(e[6]), boss = Nil(e[7]), writer = writer, entrants = entrants, rounds = rounds,
			winners = Guids(log, e[11]), greed = Nil(e[12]) }
	elseif e[1] == CHANGE then
		local c = e[3]
		c.id, c.by = Guid(log, c.id), Guid(log, c.by)
		if c.losers then c.losers = Guids(log, c.losers) end
		if c.winners then c.winners = Guids(log, c.winners) end
		if type(c.time) == "number" then c.time = time - c.time end
		return { kind = "change", time = time, change = c }
	end
	e.time = time
	if e.id then e.id = Guid(log, e.id) end
	if e.by then e.by = Guid(log, e.by) end
	return e
end

-- A value serialised, deflated and base64'd; or the value itself if the game can't compress.
local function Squeeze(value)
	local util = C_EncodingUtil
	if util and util.CompressString and util.EncodeBase64 then
		local ok, packed = pcall(util.CompressString, ns.Serialize(value), DEFLATE)
		if ok and type(packed) == "string" then return util.EncodeBase64(packed) end
	end
	return value
end

local function Unsqueeze(packed)
	if type(packed) ~= "string" then return packed end
	local util = C_EncodingUtil
	local ok, text = pcall(function() return util.DecompressString(util.DecodeBase64(packed), DEFLATE) end)
	return ok and type(text) == "string" and ns.Deserialize(text) or {}
end

-- A chunk of events, packed.
local function PackChunk(log, events)
	local list, last = {}, nil
	for i, event in ipairs(events) do
		local time = tonumber(event.time) or 0
		list[i] = Compact(log, event, last and time - last or time)
		last = time
	end
	return Squeeze(list)
end

local function UnpackChunk(log, chunk)
	local list = Unsqueeze(chunk)
	local events, time = {}, 0
	for i, e in ipairs(list) do
		e = ns.Copy(e)
		time = time + (tonumber(e[1] and e[2] or e.time) or 0) -- the first event's gap is its own time
		events[i] = Expand(log, e, time)
	end
	return events
end

-- The wins kept for checking (Sync.lua): need wins this client saw (in rolls it watched, or on an officer's client
-- any result it heard of), and lifted lockouts, the newest 100.
local function AddWin(log, entry)
	local wins = log.wins
	wins[#wins + 1] = entry
	latest[Key(entry.id, entry.item)] = entry
	while #wins > WINS_KEPT do
		local old = table.remove(wins, 1)
		local key = Key(old.id, old.item)
		if latest[key] == old then latest[key] = nil end
	end
end

local function NoteWins(log, event)
	local change = event.kind == "change" and type(event.change) == "table" and event.change
	if event.kind == "award" and not event.greed then
		for _, id in ipairs(event.winners or {}) do
			AddWin(log, { id = id, item = event.item, time = event.time, writer = event.writer, sid = event.sid })
		end
	elseif change and change.op == "result" then
		for _, id in ipairs(change.winners or {}) do
			AddWin(log, { id = id, item = change.item, time = change.time, writer = ns.NameOf(change.by), sid = "" })
		end
	elseif change and change.op == "adjust" and change.won then
		AddWin(log, { id = change.id, item = change.item, time = change.time, writer = ns.NameOf(change.by), sid = "" })
	elseif change and change.op == "adjust" and change.unlock then
		AddWin(log, { id = change.id, item = change.item, time = change.time, unlock = true })
	end
end

-- This guild's log; a new one if there's none in this layout yet (unreleased: an older layout just starts again).
-- The first time it's used after logging in, events packed at logout are unpacked again.
local function Log()
	if not ns.saved or not ns.guild then return nil end
	ns.saved.log = ns.saved.log or {}
	local log = ns.saved.log[ns.guild]
	if type(log) ~= "table" or type(log.chunks) ~= "table" then
		log = { players = {}, chunks = {}, open = {}, wins = {} }
		ns.saved.log[ns.guild] = log
	end
	if current ~= log then
		current, latest = log, {}
		if log.packedWins then
			log.wins = {}
			for i, w in ipairs(Unsqueeze(log.packedWins)) do
				log.wins[i] = { id = Guid(log, w[1]), item = w[2], time = w[3], writer = Nil(w[4]), sid = Nil(w[5]), unlock = Nil(w[6]) }
			end
			log.packedWins = nil
		end
		if log.tail then
			local open = UnpackChunk(log, log.tail)
			for _, event in ipairs(log.open) do open[#open + 1] = event end
			log.open, log.tail = open, nil
		end
		for _, entry in ipairs(log.wins) do latest[Key(entry.id, entry.item)] = entry end
	end
	return log
end

-- At logout (or a reload) the events not yet in a chunk are packed too, so the saved log is all packed.
ns.On("PLAYER_LOGOUT", function()
	for _, log in pairs(ns.saved and ns.saved.log or {}) do
		if type(log) == "table" and type(log.open) == "table" and log.open[1] and not log.tail then
			log.tail, log.open = PackChunk(log, log.open), {}
		end
		if type(log) == "table" and type(log.wins) == "table" and log.wins[1] and not log.packedWins then
			local list = {}
			for i, w in ipairs(log.wins) do
				list[i] = { Place(log, w.id), w.item, w.time, False(w.writer), False(w.sid), False(w.unlock) }
			end
			log.packedWins, log.wins = Squeeze(list), {}
		end
	end
	current = nil
end)

function ns.LogEvent(event)
	local log = Log()
	if not log then return end
	event.time = event.time or GetServerTime()
	log.open[#log.open + 1] = event
	NoteWins(log, event)
	if #log.open >= LOG_CHUNK then
		log.chunks[#log.chunks + 1] = PackChunk(log, log.open)
		log.open = {}
		while #log.chunks > LOG_CHUNKS do table.remove(log.chunks, 1) end
	end
end

-- Every event in the log, oldest first (unpacking every chunk: for tools and checks, not every roll).
function ns.LogEvents()
	local log = Log()
	local events = {}
	if not log then return events end
	for _, chunk in ipairs(log.chunks) do
		for _, event in ipairs(UnpackChunk(log, chunk)) do events[#events + 1] = event end
	end
	for _, event in ipairs(log.open) do events[#events + 1] = event end
	return events
end

-- A player's name as the log last had it, for players the roster no longer knows.
function ns.LoggedName(guid)
	local log = Log()
	for _, player in ipairs(log and log.players or {}) do
		if player[1] == guid then return player[2] end
	end
end

-- Checks the ledger against the log (/pl log): replays what the log says happened to each player's pity on each item,
-- from the most recent fact it has about it (a roll's pity, a win, a row an officer sent), and compares the outcome
-- with the ledger. A member checks their own row; an officer their whole table, from the last time it took another
-- officer's (whose merged changes its log never saw); or with `beforeLast`, from the one before that, to see what
-- taking the last one (a resync) lost. Leavers are skipped, as their pity decays. Returns how many were checked, the
-- mismatches ({ guid, item, ledger, log, at }, cells as codes, false for none), and that time, if any.
function ns.CheckLog(beforeLast)
	local events = ns.LogEvents()
	local officer = ns.HoldsTable()
	local me = UnitGUID("player")
	local from, since, passing = 1, nil, beforeLast and 1 or 0
	if officer then
		for i = #events, 1, -1 do
			if events[i].kind == "base" then
				if passing == 0 then
					from, since = i + 1, events[i].time
					break
				end
				passing = passing - 1
			end
		end
	end
	-- In the order they took effect in the table: a change by its own time.
	local list = {}
	for i = from, #events do
		local e = events[i]
		local time = e.kind == "change" and type(e.change) == "table" and tonumber(e.change.time) or e.time
		list[#list + 1] = { e = e, time = time or 0, i = i }
	end
	table.sort(list, function(a, b)
		if a.time ~= b.time then return a.time < b.time end
		return a.i < b.i
	end)
	local WON, MAX = ns.CELL_WON, 4
	local expect, at, skip = {}, {}, {}
	local function Set(guid, item, cell, time)
		if officer or guid == me then
			expect[guid .. ":" .. item], at[guid .. ":" .. item] = cell, time
		end
	end
	local function Move(guid, item, steps, time)
		local key = guid .. ":" .. item
		local cell = expect[key]
		if cell == nil or cell == WON then return end -- nothing known to start from, or a win, which stays
		local pity = math.max(math.min((cell and cell + 1 or 0) + steps, MAX + 1), 0)
		expect[key], at[key] = pity > 0 and pity - 1 or false, time
	end
	for _, entry in ipairs(list) do
		local e, time = entry.e, entry.time
		local c = e.kind == "change" and type(e.change) == "table" and e.change
		if e.kind == "award" and not e.greed and type(e.entrants) == "table" then
			local won = {}
			for _, id in ipairs(e.winners or {}) do won[id] = true end
			for id, entrant in pairs(e.entrants) do
				if won[id] then
					Set(id, e.item, WON, time)
				elseif type(entrant.pity) == "number" then
					Set(id, e.item, math.min(entrant.pity / 10, MAX), time)
				end
			end
		elseif c and c.op == "result" then
			for _, id in ipairs(c.winners or {}) do Set(id, c.item, WON, time) end
			for _, id in ipairs(c.losers or {}) do Move(id, c.item, 1, time) end
		elseif c and c.op == "adjust" and c.won then
			Set(c.id, c.item, WON, time)
		elseif c and c.op == "adjust" then
			local key = c.id .. ":" .. c.item
			if c.unlock and expect[key] == WON then expect[key] = false end
			if not c.unlock or expect[key] ~= nil then Move(c.id, c.item, c.steps or 0, time) end
		elseif c and (c.op == "leave" or c.op == "rejoin") then
			skip[c.id] = true
		elseif e.kind == "row" and type(e.cells) == "table" then
			for item, cell in pairs(e.cells) do Set(me, item, cell, time) end
		end
	end
	local checked, mismatches = 0, {}
	for key, cell in pairs(expect) do
		local guid, item = key:match("^(.*):(%d+)$")
		item = tonumber(item)
		if guid and item and not skip[guid] and not (ns.ledger and ns.ledger.data.leavers[guid]) then
			checked = checked + 1
			local actual = ns.ledger and ns.ledger:Cell(guid, item)
			if actual == nil then actual = false end
			if actual ~= cell then mismatches[#mismatches + 1] = { guid, item, actual, cell, at[key] } end
		end
	end
	return checked, mismatches, since
end

-- A player's last need win of an item among the wins kept, unless a lifted lockout came after: { id, item, time,
-- writer, sid }, or nil.
function ns.LoggedWin(guid, item)
	if not Log() then return nil end
	local entry = latest[Key(guid, item)]
	return entry and not entry.unlock and entry or nil
end

-- When this client saw an officer lift a player's lockout on an item, if that's the latest it saw of it.
function ns.LoggedUnlock(guid, item)
	if not Log() then return nil end
	local entry = latest[Key(guid, item)]
	return entry and entry.unlock and entry.time or nil
end
