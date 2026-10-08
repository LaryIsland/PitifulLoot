local _, ns = ...

-- Live rolls (5.1). The writer runs the real roll and tells the group what happens. Everyone, the writer included,
-- keeps a mirror of the roll to show, and everyone else checks it against the /roll messages they saw and their own
-- copy of the ledger (6.1). Messages on the live prefix, all from the writer except query:
--
--   writer  {}                                       an officer claiming the writer role
--   open    {sid, item, copies, greed, opened, secs} a roll starts
--   rolls   {sid, round, list}                       rolls counted ({id, name, roll, pity, os}) or refused ({name, roll, why})
--   os      {sid, id, os}                            the writer corrected an off-spec flag
--   reroll  {sid, round, ids, slots, winners, secs}  a tie that needs rolling off
--   decided {sid, winners}
--   cancel  {sid}
--   awarded {sid, rev}                               recorded in the ledger as revision `rev`
--   query   {}                                       anyone: who's the writer, and what's happening?
--   state   {mirror, left}                           the writer's reply

local LIVE = ns.PREFIX_LIVE
local FLUSH_DELAY = 0.5
local LATE_GRACE = 10 -- seconds after a roll is decided that late /rolls are still answered with a refusal

local live = { observed = {} }
ns.live = live

local engine -- the writer's ns.NewSession behind the mirror
local closeTimer
local pending, pendingRound, flushing = {}, nil, false
local count = 0
local queried = false

local function GroupChannel()
	return IsInRaid() and "RAID" or "PARTY"
end

local function SendLive(kind, data, target)
	if not IsInGroup() then return end
	ns.Send(LIVE, kind, data, target and "WHISPER" or GroupChannel(), target)
end

local function Announce(text)
	if ns.settings.announce and IsInGroup() then
		ChatThrottleLib:SendChatMessage("NORMAL", ns.PREFIX_LIVE, "Pitiful Loot: " .. text, GroupChannel())
	else
		ns.Print(text)
	end
end

function ns.AmWriter()
	return live.writer ~= nil and ns.IsMe(live.writer)
end

local function IsActive(m)
	return m ~= nil and (m.state == "open" or m.state == "reroll")
end

local function NameList(ids)
	local names = {}
	for i, id in ipairs(ids) do names[i] = ns.NameOf(id) end
	return table.concat(names, ", ")
end

-- "Lary: roll 62, pity +50, off-spec -20 = 92", using the last round the player rolled in.
local function Breakdown(m, id)
	local entrant = m.entrants[id]
	local round, roll
	for r = #m.rounds, 1, -1 do
		if m.rounds[r][id] then round, roll = r, m.rounds[r][id] break end
	end
	if not entrant or not roll then return ns.NameOf(id) end
	local parts = { ("%s: roll %d, pity +%d"):format(entrant.name or ns.NameOf(id), roll, entrant.pity) }
	if entrant.offSpec then parts[#parts + 1] = ("off-spec %d"):format(ns.OFFSPEC_MODIFIER) end
	local text = table.concat(parts, ", ") .. " = " .. ns.EffectiveRoll(roll, ns.Bonus(entrant.pity, entrant.offSpec))
	return round > 1 and text .. " (reroll)" or text
end
ns.Breakdown = Breakdown

-- Builds a session from the mirror, for a new writer taking over or to check the writer's result. closeLast closes
-- the round the mirror is on as well as the ones before it.
local function Rebuild(m, closeLast)
	local session = ns.NewSession(m.item, m.copies, m.greed)
	for r = 1, m.round do
		for id, roll in pairs(m.rounds[r] or {}) do
			local entrant = m.entrants[id]
			if entrant then session:AddRoll(id, roll, entrant.pity, entrant.offSpec) end
		end
		if r < m.round or closeLast then session:CloseRound() end
	end
	return session
end

local function SameMembers(a, b)
	local set = {}
	for _, id in ipairs(a) do set[id] = true end
	for _, id in ipairs(b) do
		if not set[id] then return false end
		set[id] = nil
	end
	return next(set) == nil
end

-- Checks a finished round against what this client saw: each counted roll, each roll the writer left out, and the
-- pity the writer used. A client that joined part way through can't, and doesn't.
local function VerifyRound(m, round)
	if ns.AmWriter() or m.partial then return end
	local counted = m.rounds[round] or {}
	local refused = {}
	for _, r in ipairs(m.rejects) do
		local member = r.round >= round and ns.GroupMember(r.name)
		if member then refused[member.guid] = true end
	end
	for id, roll in pairs(counted) do
		local seen = live.observed[id] and live.observed[id][round]
		if seen == nil then
			ns.Warn(("%s: the writer counted a roll of %d that you didn't see."):format(ns.NameOf(id), roll))
		elseif seen ~= roll then
			ns.Warn(("%s: the writer counted a roll of %d, but you saw %d."):format(ns.NameOf(id), roll, seen))
		end
	end
	for id, rounds in pairs(live.observed) do
		if rounds[round] and counted[id] == nil and not refused[id] then
			ns.Warn(("%s rolled %d, but the writer didn't count it."):format(ns.NameOf(id), rounds[round]))
		end
	end
	if round == 1 and ns.ledger then
		for id, entrant in pairs(m.entrants) do
			local mine = ns.ledger.state:GetPity(id, m.item, m.greed, m.opened)
			if mine ~= entrant.pity then
				ns.Warn(("%s: the writer used pity %d, but your ledger (revision %d) says %d.")
					:format(ns.NameOf(id), entrant.pity, (ns.ledger:Revision()), mine))
			end
		end
	end
end

local function VerifyWinners(m)
	if ns.AmWriter() or m.partial then return end
	if not SameMembers(Rebuild(m, true).winners, m.winners) then
		ns.Warn("The winners the writer announced don't match the rolls.")
	end
end

-- Checks a ledger entry for a roll this client watched against the mirror.
function ns.CheckEntry(entry)
	local m = live.mirror
	if ns.AmWriter() or not m or m.partial or entry.type ~= "award" or entry.sid ~= m.sid then return end
	local same = ns.Serialize(entry.rounds) == ns.Serialize(m.rounds) and SameMembers(entry.winners, m.winners)
	for id, recorded in pairs(entry.entrants) do
		local seen = m.entrants[id]
		if not seen or seen.pity ~= recorded.pity or (seen.offSpec or false) ~= (recorded.offSpec or false) then same = false end
	end
	if not same then
		ns.Warn(("Revision %d, recorded by %s, doesn't match the roll you watched."):format(entry.rev, tostring(entry.by)))
	end
end

-- Odds -----------------------------------------------------------------------------------------------------------

-- The pool is everyone who has rolled plus anyone in the group with pity on the item, who is assumed to be about to
-- (5.2). In a reroll it's the tied players, for the copies left.
local function RefreshOdds()
	local m = live.mirror
	if not IsActive(m) then return end
	local pool, copies = {}, m.copies
	if m.state == "open" then
		for id, entrant in pairs(m.entrants) do
			pool[#pool + 1] = { id = id, pity = entrant.pity, offSpec = entrant.offSpec }
		end
		local state = ns.ledger and ns.ledger.state
		if state then
			for _, member in ipairs(ns.GroupMembers()) do
				local id = member.guid
				if not m.entrants[id] and not state:HasWon(id, m.item) then
					local pity = state:GetPity(id, m.item, m.greed, m.opened)
					if pity > 0 then pool[#pool + 1] = { id = id, pity = pity } end
				end
			end
		end
	else
		copies = m.slots
		for id in pairs(m.contenders) do
			local entrant = m.entrants[id]
			pool[#pool + 1] = { id = id, pity = entrant.pity, offSpec = entrant.offSpec }
		end
	end
	ns.OddsLater(pool, copies, function(chances)
		if live.mirror ~= m then return end
		m.odds = chances
		ns.Fire("SESSION_CHANGED")
	end)
end

-- The mirror -----------------------------------------------------------------------------------------------------

local Mirror, Valid = {}, {}

local function IsCount(n)
	return type(n) == "number" and n >= 1 and n % 1 == 0
end

function Valid.open(d)
	return type(d.sid) == "string" and type(d.item) == "number" and IsCount(d.copies) and type(d.opened) == "number"
		and type(d.secs) == "number"
end
function Mirror.open(d)
	live.mirror = {
		sid = d.sid, item = d.item, copies = d.copies, greed = d.greed, opened = d.opened,
		state = "open", round = 1, ends = GetTime() + d.secs,
		entrants = {}, rounds = { {} }, winners = {}, rejects = {},
	}
	live.observed = {}
end

function Valid.rolls(d)
	if not IsCount(d.round) or type(d.list) ~= "table" then return false end
	for _, r in ipairs(d.list) do
		if type(r) ~= "table" or type(r.name) ~= "string" or type(r.roll) ~= "number" then return false end
		if not r.why and (type(r.id) ~= "string" or (d.round == 1 and type(r.pity) ~= "number")) then return false end
	end
	return true
end
function Mirror.rolls(d, m)
	for _, r in ipairs(d.list) do
		if r.why then
			m.rejects[#m.rejects + 1] = { round = d.round, name = r.name, roll = r.roll, why = r.why }
		else
			if d.round == 1 then
				m.entrants[r.id] = { name = r.name, pity = r.pity, offSpec = r.os or nil, unknownSpec = r.unknown or nil }
			end
			m.rounds[d.round] = m.rounds[d.round] or {}
			m.rounds[d.round][r.id] = r.roll
		end
	end
end

function Valid.os(d)
	return type(d.id) == "string"
end
function Mirror.os(d, m)
	local entrant = m.entrants[d.id]
	if entrant then
		entrant.offSpec = d.os or nil
		entrant.unknownSpec = nil
	end
end

function Valid.reroll(d)
	return IsCount(d.round) and type(d.ids) == "table" and IsCount(d.slots) and type(d.secs) == "number"
end
function Mirror.reroll(d, m)
	VerifyRound(m, m.round)
	m.state, m.round, m.slots, m.ends = "reroll", d.round, d.slots, GetTime() + d.secs
	m.winners = type(d.winners) == "table" and d.winners or {}
	m.contenders = {}
	for _, id in ipairs(d.ids) do m.contenders[id] = true end
	m.rounds[d.round] = m.rounds[d.round] or {}
end

function Valid.decided(d)
	return type(d.winners) == "table"
end
function Mirror.decided(d, m)
	VerifyRound(m, m.round)
	m.state, m.winners, m.ends, m.closed = "decided", d.winners, nil, GetTime()
	VerifyWinners(m)
end

function Valid.cancel()
	return true
end
function Mirror.cancel(_, m)
	m.state, m.ends = "cancelled", nil
end

function Valid.awarded(d)
	return type(d.rev) == "number"
end
function Mirror.awarded(d, m)
	m.state, m.rev = "awarded", d.rev
end

local function Changed(kind)
	if kind == "open" and ns.settings.autoShow and ns.ShowWindow then ns.ShowWindow() end
	RefreshOdds()
	ns.Fire("SESSION_CHANGED")
end

for kind, apply in pairs(Mirror) do
	ns.Receive(LIVE, kind, function(d, sender)
		if type(d) ~= "table" or not ns.SameName(sender, live.writer) or not Valid[kind](d) then return end
		if kind ~= "open" and not (live.mirror and live.mirror.sid == d.sid) then return end
		apply(d, live.mirror)
		Changed(kind)
	end)
end

-- The writer --------------------------------------------------------------------------------------------------

local function Flush()
	local m = live.mirror
	if pending[1] and m then SendLive("rolls", { sid = m.sid, round = pendingRound, list = pending }) end
	pending, pendingRound = {}, nil
end

-- Applies a writer's message to its own mirror, then sends it. Rolls are batched; anything else sends them first.
local function Emit(kind, data)
	Flush()
	Mirror[kind](data, live.mirror)
	Changed(kind)
	SendLive(kind, data)
end

local function QueueRoll(r)
	local m = live.mirror
	Mirror.rolls({ round = m.round, list = { r } }, m)
	pending[#pending + 1] = r
	pendingRound = m.round
	if not flushing then
		flushing = true
		C_Timer.After(FLUSH_DELAY, function()
			flushing = false
			Flush()
		end)
	end
	Changed("rolls")
end

local function StopWriting()
	engine = nil
	if closeTimer then closeTimer:Cancel() end
	closeTimer = nil
	pending, pendingRound = {}, nil
end

local function ScheduleClose(secs)
	if closeTimer then closeTimer:Cancel() end
	closeTimer = C_Timer.NewTimer(secs, function()
		closeTimer = nil
		ns.CloseRound()
	end)
end

-- A /roll seen by the writer: counted, or refused with a reason everyone can see.
local function WriterRoll(name, roll, low, high)
	local m = live.mirror
	if not engine or not m then return end
	local function Refuse(why)
		QueueRoll({ name = name, roll = roll, why = why })
	end
	if not IsActive(m) then
		if m.state == "decided" and m.closed and GetTime() - m.closed < LATE_GRACE then Refuse("too late") end
		return
	end
	if low ~= ns.ROLL_MIN or high ~= ns.ROLL_MAX then return Refuse(("rolled %d-%d"):format(low, high)) end
	local member = ns.GroupMember(name)
	if not member then return Refuse("not in the group") end
	local id, pity, offSpec = member.guid, nil, nil
	if m.round == 1 then
		local state = ns.ledger.state
		if state:HasWon(id, m.item) then return Refuse("already won this item") end
		if not ns.CanUse(id, m.item) then return Refuse("can't use this item") end
		pity = state:GetPity(id, m.item, m.greed, m.opened)
		offSpec = ns.IsOffSpec(id, m.item)
	end
	local ok, why = engine:AddRoll(id, roll, pity, offSpec)
	if not ok then return Refuse(why) end
	QueueRoll({ id = id, name = member.name, roll = roll, pity = pity, os = offSpec or nil, unknown = m.round == 1 and offSpec == nil or nil })
end

-- Every /roll during a roll: the writer counts it, everyone else notes it to check the writer's result against.
ns.On("CHAT_MSG_SYSTEM", function(message)
	local name, roll, low, high = ns.ParseRoll(message)
	if not name then return end
	local m = live.mirror
	if IsActive(m) and low == ns.ROLL_MIN and high == ns.ROLL_MAX then
		local member = ns.GroupMember(name)
		if member then
			local seen = live.observed[member.guid] or {}
			live.observed[member.guid] = seen
			if seen[m.round] == nil then seen[m.round] = roll end
		end
	end
	if ns.AmWriter() then WriterRoll(name, roll, low, high) end
end)

-- Takes the writer role (6.2), and takes over a roll already in progress from the mirror.
function ns.ClaimWriter()
	if not IsInGroup() then return ns.Print("You need to be in a group.") end
	if not ns.IsOfficer(ns.PlayerName()) then return ns.Print("Only officers can be the writer.") end
	if not ns.ledger then return ns.Print("Your guild's ledger hasn't loaded yet.") end
	live.writer = ns.PlayerName()
	SendLive("writer", {})
	local m = live.mirror
	if m and (IsActive(m) or m.state == "decided") then
		engine = Rebuild(m, m.state == "decided")
		if IsActive(m) then ScheduleClose(math.max((m.ends or GetTime()) - GetTime(), 5)) end
		Announce(("%s has taken over the roll for %s."):format(ns.PlayerName(), ns.ItemLink(m.item)))
	else
		Announce(ns.PlayerName() .. " is running loot rolls.")
	end
	ns.InspectGroup()
	ns.Fire("SESSION_CHANGED")
end

function ns.StartRoll(item, copies, greed)
	if not ns.AmWriter() then return ns.Print("Only the writer can start a roll. An officer becomes the writer with /pl writer.") end
	if ns.SyncBusy() then return ns.Print("Wait until your ledger has finished syncing.") end
	local m = live.mirror
	if IsActive(m) or (m and m.state == "decided" and m.winners[1]) then
		return ns.Print("Award or cancel the current roll first.")
	end
	copies = copies or 1
	count = count + 1
	local opened = GetServerTime()
	engine = ns.NewSession(item, copies, greed)
	Emit("open", {
		sid = ("%s:%d:%d"):format(ns.PlayerName(), opened, count),
		item = item, copies = copies, greed = greed or nil, opened = opened, secs = ns.settings.rollTime,
	})
	local what = copies > 1 and ("%s (%d copies)"):format(ns.ItemLink(item), copies) or ns.ItemLink(item)
	Announce(("%sroll for %s: /roll now (%ds)."):format(greed and "greed " or "", what, ns.settings.rollTime))
	ScheduleClose(ns.settings.rollTime)
end

function ns.CloseRound()
	local m = live.mirror
	if not ns.AmWriter() or not engine or not IsActive(m) then return end
	if closeTimer then closeTimer:Cancel() end
	closeTimer = nil
	Flush()
	local result, tied = engine:CloseRound()
	if result == "reroll" then
		local secs = ns.settings.rerollTime
		Emit("reroll", {
			sid = m.sid, round = #engine.rounds, ids = tied, slots = engine.slots,
			winners = ns.Copy(engine.winners), secs = secs,
		})
		Announce(("tie for %s between %s: /roll again (%ds)."):format(ns.ItemLink(m.item), NameList(tied), secs))
		ScheduleClose(secs)
		return
	end
	Emit("decided", { sid = m.sid, winners = ns.Copy(engine.winners) })
	if not engine.winners[1] then
		Announce(("no one rolled for %s."):format(ns.ItemLink(m.item)))
		engine = nil
		return
	end
	Announce(("%s goes to %s."):format(ns.ItemLink(m.item), NameList(engine.winners)))
	for _, id in ipairs(engine.winners) do Announce(Breakdown(m, id)) end
end

-- Records the roll in the ledger, which is when the losers gain pity (4.1), and hands out the item.
function ns.Award()
	local m = live.mirror
	if not ns.AmWriter() or not engine or not engine.done or not m or m.state ~= "decided" then
		return ns.Print("There's no decided roll to award.")
	end
	local entry = engine:Record()
	entry.time, entry.by, entry.sid = m.opened, ns.PlayerName(), m.sid
	for id, entrant in pairs(entry.entrants) do entrant.name = m.entrants[id] and m.entrants[id].name end
	local ok, err = ns.AppendEntry(entry)
	if not ok then return ns.Warn("The award couldn't be recorded: " .. err .. ".") end
	ns.GiveLoot(m.item, engine.winners)
	engine = nil
	Emit("awarded", { sid = m.sid, rev = entry.rev })
end

function ns.CancelRoll()
	local m = live.mirror
	if not ns.AmWriter() or not m or not (IsActive(m) or m.state == "decided") then return end
	StopWriting()
	Emit("cancel", { sid = m.sid })
	Announce(("the roll for %s was cancelled."):format(ns.ItemLink(m.item)))
end

-- The writer's correction of a roll's off-spec flag, before the first round closes.
function ns.ToggleOffSpec(id)
	local m = live.mirror
	if not ns.AmWriter() or not engine or not m or m.state ~= "open" or not m.entrants[id] then return end
	local offSpec = not m.entrants[id].offSpec
	if engine:SetOffSpec(id, offSpec) then Emit("os", { sid = m.sid, id = id, os = offSpec or nil }) end
end

-- Handover and late joiners ---------------------------------------------------------------------------------------

ns.Receive(LIVE, "writer", function(_, sender)
	if not ns.IsOfficer(sender) then return end
	if ns.AmWriter() then
		StopWriting()
		ns.Print(sender .. " has taken over as the writer.")
	end
	live.writer = sender
	ns.Fire("SESSION_CHANGED")
end)

ns.Receive(LIVE, "query", function(_, sender)
	if not ns.AmWriter() then return end
	local m = live.mirror and ns.Copy(live.mirror)
	if m then m.odds, m.ends = nil, nil end
	SendLive("state", { mirror = m, left = live.mirror and live.mirror.ends and live.mirror.ends - GetTime() }, sender)
end)

ns.Receive(LIVE, "state", function(d, sender)
	if type(d) ~= "table" or not ns.IsOfficer(sender) then return end
	live.writer = sender
	local m = d.mirror
	if type(m) == "table" and type(m.sid) == "string" and type(m.entrants) == "table" and type(m.rounds) == "table" then
		m.partial = true
		m.ends = type(d.left) == "number" and GetTime() + d.left or nil
		live.mirror, live.observed = m, {}
	end
	Changed("state")
end)

ns.On("GROUP_ROSTER_UPDATE", function()
	if not IsInGroup() then
		StopWriting()
		live.writer, live.mirror, live.observed, queried = nil, nil, {}, false
	else
		if live.writer and not ns.GroupMember(live.writer) then
			ns.Print(live.writer .. ", the writer, has left the group. Another officer can take over with /pl writer.")
			live.writer = nil
		end
		if ns.AmWriter() then ns.InspectGroup() end
		if not queried then
			queried = true
			SendLive("query", {})
		end
	end
	ns.Fire("SESSION_CHANGED")
end)

-- The roll as rows for the window: everyone who rolled or is expected to, winners first.
function ns.SessionRows()
	local m = live.mirror
	if not m then return {} end
	local rows, byId = {}, {}
	local function Row(id)
		if not byId[id] then
			byId[id] = { id = id, name = ns.NameOf(id) }
			rows[#rows + 1] = byId[id]
		end
		return byId[id]
	end
	for id, entrant in pairs(m.entrants) do
		local row = Row(id)
		row.name, row.pity, row.offSpec, row.unknownSpec = entrant.name or row.name, entrant.pity, entrant.offSpec, entrant.unknownSpec
	end
	for r = 1, #m.rounds do
		for id, roll in pairs(m.rounds[r]) do
			local row = Row(id)
			row.roll, row.round = roll, r
		end
	end
	for id, chance in pairs(m.odds or {}) do Row(id).odds = chance end
	for _, id in ipairs(m.winners or {}) do Row(id).winner = true end
	for _, row in ipairs(rows) do
		if not row.pity and ns.ledger then row.pity = ns.ledger.state:GetPity(row.id, m.item, m.greed, m.opened) end
		if row.roll then row.total = ns.EffectiveRoll(row.roll, ns.Bonus(row.pity or 0, row.offSpec)) end
		row.contender = m.contenders and m.contenders[row.id] or nil
	end
	table.sort(rows, function(a, b)
		if (a.winner or false) ~= (b.winner or false) then return a.winner == true end
		if (a.total or -1000) ~= (b.total or -1000) then return (a.total or -1000) > (b.total or -1000) end
		if (a.odds or 0) ~= (b.odds or 0) then return (a.odds or 0) > (b.odds or 0) end
		return a.name < b.name
	end)
	return rows
end
