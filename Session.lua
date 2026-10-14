local _, ns = ...
local L, CHAT = ns.L, ns.CHAT

-- Live rolls (5.1). The writer runs the real roll and tells the group what happens. Everyone, the writer included,
-- keeps a mirror of the roll to show, and everyone else checks it against the /roll messages they saw and their own
-- copy of the ledger (6.1). Messages on the live prefix, all from the writer except query:
--
--   writer  {}                                       an officer claiming the writer role
--   open    {sid, item, copies, greed, opened, secs, instance, boss} a roll starts (and where the item dropped)
--   rolls   {sid, round, list}                       rolls counted ({id, name, roll, pity, os}) or refused ({name, roll, why,
--                                                    low, high}, why being a code: late, range, raid, won, cantuse or
--                                                    AddRoll's; low and high the range rolled, for range)
--   os      {sid, id, os, unknown}                   the writer corrected an off-spec flag (`unknown`: by a fallback role)
--   reroll  {sid, round, ids, slots, winners, secs}  a tie that needs rolling off
--   decided {sid, winners}
--   cancel  {sid}
--   awarded {sid, rev, given}                        recorded in the ledger as revision `rev`; `given` got theirs by
--                                                    master loot, so there's nothing to trade them
--   disenchant {sid, sell}                           no one rolled on a BoP item, so it's to be disenchanted; or with
--                                                    `sell`, no one greed-rolled on a BoE, so it's kept to be sold
--   pass    {sid, round}                             anyone: they won't roll in this round
--   query   {role, why}                              anyone: who's the writer, and what's happening? (and their role, or
--                                                    why their talents don't settle one: nocapstone, ambiguous)
--   state   {mirror, left}                           the writer's reply
--   here    {role, why}                              anyone, to a new writer: this player has the addon, and the role
--                                                    their talents suggest (ns.MyRole), which they resend if it changes
--   roles   {r}                                      the writer's view of everyone's role ({guid = {role, source}})
--   setrole {id, role}                               an officer: that raider's role from now on (none: work it out)
--   inspected {id, role, why}                        an officer, to the writer: the role their inspect of a raider read,
--                                                    or why it couldn't (ns.UNKNOWN_REASONS)

local LIVE = ns.PREFIX_LIVE
local FLUSH_DELAY = 0.5
local LATE_GRACE = 10 -- seconds after a roll is decided that late /rolls are still answered with a refusal
local AUTO_ROLL_DELAY = 5 -- seconds auto-roll waits in a new roll, so there's time to pass
local CLOSING_WARNING = 5 -- seconds before a roll closes that raid chat is told, for players without the addon
local TIE_QUIET = 1.5 -- seconds a tie waits before raid chat hears of it, so instant rerolls don't fill raid chat
local EARLY_END = 1 -- seconds the opening round waits once everyone who can roll has, before it ends early
local INTRO_WAIT = 10 -- seconds the writer gives a player's addon to answer before taking it they haven't got one
local INTRO_AGAIN = 12 * 60 * 60 -- seconds before a player without the addon is whispered about it again: once a night

local live = { observed = {} }
ns.live = live

local engine -- the writer's ns.NewSession behind the mirror
local closeTimer
local pending, pendingRound, flushing = {}, nil, false
local count = 0
local queried = false
local autoRollTimer, warnTimer, tieTimer, earlyTimer
local rolesSent -- the roles the writer last told the group, serialized
-- Players the writer knows have the addon (by GUID), who aren't whispered when a roll doesn't count: their window
-- says why (ns.MyRefusal).
local users = {}

local function GroupChannel()
	return IsInRaid() and "RAID" or "PARTY"
end

local function SendLive(kind, data, target)
	if not IsInGroup() then return end
	ns.Send(LIVE, kind, data, target and "WHISPER" or GroupChannel(), target)
end

-- Announcements go to raid chat (party chat in a party), never /say, so everyone in the group sees them with or
-- without the addon. Headlines (a roll starting, a tie, the result) are raid warnings when the writer is allowed to
-- send them, so nobody misses a roll.
local CHANNEL_LABELS = { PARTY = "Party", RAID = "Raid", RAID_WARNING = "Raid Warning" }

-- The name you go by as the writer, on screen and in raid chat: your own, or on the test menu's raider page the
-- made-up officer's (TestCommands.lua), so it reads as it would in a raid.
local function MyWriterName()
	local _, name = ns.TestOfficer()
	return name or ns.PlayerName()
end

-- The writer as the window shows them (a name, or the made-up officer's GUID, for ns.ColoredName).
function ns.WriterShownAs()
	return (ns.TestOfficer()) or live.writer
end

-- Test mode, unless someone in the group is trusted (ns.TestIsPrivate): shows what the group would see, only to you;
-- on your own, as if you led a raid. Each line goes in your chat in its channel's colour, and headlines also appear
-- in the middle of the screen like raid warnings.
local function Preview(text, channel)
	local line = ("[%s] %s: %s"):format(CHANNEL_LABELS[channel], MyWriterName(), text)
	local color = C_ChatInfo.GetColorForChatType and C_ChatInfo.GetColorForChatType(channel)
	if color then line = ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, line) end
	DEFAULT_CHAT_FRAME:AddMessage(line)
	if channel == "RAID_WARNING" and RaidWarningUtil and ChatTypeInfo then
		RaidWarningUtil.AddMessage(text, ChatTypeInfo.RAID_WARNING)
	end
end

local function Announce(text, headline)
	local grouped = IsInGroup()
	if not ns.settings.announce or not (grouped or ns.IsTestMode()) then return ns.Print(text) end
	local channel = grouped and GroupChannel() or "RAID"
	local canWarn = not grouped
		or IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") or IsEveryoneAssistant())
	if headline and ns.settings.raidWarning and canWarn then channel = "RAID_WARNING" end
	ns.Capture("announce", channel, text)
	if not grouped or ns.TestIsPrivate() then return Preview(text, channel) end
	ChatThrottleLib:SendChatMessage("NORMAL", ns.PREFIX_LIVE, text, channel)
end

function ns.AmWriter()
	return live.writer ~= nil and ns.IsMe(live.writer)
end

local function IsActive(m)
	return m ~= nil and (m.state == "open" or m.state == "reroll")
end

-- A player's pity on the roll's item: none on a greed roll (4.8). Everyone's comes from what the writer sent as the roll
-- started (m.pool), so every client works the odds out alike; your own, if it isn't there, from your own row, and the
-- writer's from its table (6.3).
local function PityIn(m, id)
	if m.greed then return 0 end
	if m.pool and m.pool[id] then return m.pool[id] end
	if id == UnitGUID("player") or ns.AmWriter() then return ns.PityOf(id, m.item) end
	return 0
end

local function NameList(ids)
	local names = {}
	for i, id in ipairs(ids) do names[i] = ns.NameOf(id) end
	return table.concat(names, ", ")
end

-- "Lary: 62 + 50 pity - 20 off-spec = 92", using the last round the player rolled in. A roll with nothing added is
-- just the roll ("Mira: 90"), and one the clamp at 100 caught says so ("= 100 (max)").
local function Breakdown(m, id)
	local entrant = m.entrants[id]
	local round, roll
	for r = #m.rounds, 1, -1 do
		if m.rounds[r][id] then round, roll = r, m.rounds[r][id] break end
	end
	if not entrant or not roll then return ns.NameOf(id) end
	local text = ("%s: %d"):format(entrant.name or ns.NameOf(id), roll)
	if entrant.pity > 0 then text = CHAT.BREAKDOWN_PITY:format(text, entrant.pity) end
	if entrant.offSpec then text = CHAT.BREAKDOWN_OFFSPEC:format(text, -ns.OFFSPEC_MODIFIER) end
	local bonus = ns.Bonus(entrant.pity, entrant.offSpec)
	local total = ns.EffectiveRoll(roll, bonus)
	if entrant.pity > 0 or entrant.offSpec then
		text = ("%s = %d"):format(text, total)
		if total < roll + bonus then text = CHAT.BREAKDOWN_MAX:format(text) end
	end
	return round > 1 and CHAT.BREAKDOWN_REROLL:format(text) or text
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
			ns.Warn(L.WARN_UNSEEN_ROLL:format(ns.NameOf(id), roll))
		elseif seen ~= roll then
			ns.Warn(L.WARN_DIFFERENT_ROLL:format(ns.NameOf(id), roll, seen))
		end
	end
	for id, rounds in pairs(live.observed) do
		if rounds[round] and counted[id] == nil and not refused[id] then
			ns.Warn(L.WARN_UNCOUNTED:format(ns.NameOf(id), rounds[round]))
		end
	end
	-- Each player checks the pity used for their own roll; officers, who hold the table, check everyone's (6.1).
	if round == 1 and ns.ledger and not m.greed then
		local me = UnitGUID("player")
		for id, entrant in pairs(m.entrants) do
			if id == me or ns.HoldsTable() then
				local mine = ns.PityOf(id, m.item)
				if mine ~= entrant.pity then ns.Warn(L.WARN_PITY:format(ns.NameOf(id), entrant.pity, ns.Head().rev, mine)) end
			end
		end
	end
end

local function VerifyWinners(m)
	if ns.AmWriter() or m.partial then return end
	if not SameMembers(Rebuild(m, true).winners, m.winners) then
		ns.Warn(L.WARN_WINNERS)
	end
end

-- Checks the writer's result for a roll this client watched: the players who lost and won it are the ones who rolled.
local function CheckResult(m, change, head)
	if m.partial then return end
	local entrants = {}
	for id in pairs(m.entrants) do entrants[#entrants + 1] = id end
	local listed = {}
	for _, id in ipairs(change.losers) do listed[#listed + 1] = id end
	for _, id in ipairs(change.winners) do listed[#listed + 1] = id end
	if not SameMembers(entrants, listed) or not SameMembers(change.winners, m.winners) then
		ns.Warn(L.WARN_ENTRY:format(head.rev or 0, ns.NameOf(change.by) or tostring(change.by)))
	end
end

-- Whether a result is for the roll this client watched, which its log has as the roll itself, so an officer doesn't
-- log it twice (Pity.lua): the one its award carried, or one from the roll's writer for its item that arrives first,
-- while the roll is decided and waiting to be awarded.
function ns.WatchedRoll(change)
	local m = live.mirror
	if not m then return false end
	if m.result == nil and m.state == "decided" and m.item == change.item and live.writer
		and ns.SameName(ns.NameOf(change.by) or "", live.writer) then
		m.result = ns.DiffKey(change)
	end
	return m.result ~= nil and m.result == ns.DiffKey(change)
end

-- Notes a roll in this client's full log (6.1).
local function LogAward(m)
	ns.LogEvent({
		kind = "award", sid = m.sid, item = m.item, copies = m.copies, greed = m.greed, instance = m.instance, boss = m.boss,
		entrants = ns.Copy(m.entrants), rounds = ns.Copy(m.rounds), winners = ns.Copy(m.winners), writer = live.writer,
	})
end

-- Odds -----------------------------------------------------------------------------------------------------------

-- The pool is everyone who has rolled plus anyone in the group with pity on the item, who is assumed to be about to
-- (5.2), less anyone who passed. In a reroll it's the tied players, for the copies left.
-- If you can roll but aren't in the pool, your own chance is worked out from the pool with you added (m.myOdds),
-- leaving everyone else's figures as every other client has them.
local oddsRun = 0
local function RefreshOdds()
	local m = live.mirror
	if not IsActive(m) then return end
	local pool, copies, inPool = {}, m.copies, {}
	local function Add(id, pity, offSpec)
		pool[#pool + 1] = { id = id, pity = pity, offSpec = offSpec }
		inPool[id] = true
	end
	if m.state == "open" then
		for id, entrant in pairs(m.entrants) do Add(id, entrant.pity, entrant.offSpec) end
		for id, pity in pairs(m.pool or {}) do
			if not m.entrants[id] and not m.passed[id] then Add(id, pity) end
		end
	else
		copies = m.slots
		for id in pairs(m.contenders) do
			local entrant = m.entrants[id]
			if m.passed[id] ~= m.round then Add(id, entrant.pity, entrant.offSpec) end
		end
	end
	local me = UnitGUID("player")
	local withMe
	if ns.CanRoll() and not inPool[me] then
		withMe = { { id = me, pity = PityIn(m, me),
			offSpec = not m.greed and ns.IsOffSpec(me, m.item) or nil } }
		for i, p in ipairs(pool) do withMe[i + 1] = p end
	end
	oddsRun = oddsRun + 1
	local run = oddsRun
	ns.OddsLater(pool, copies, function(chances)
		if live.mirror ~= m or run ~= oddsRun then return end
		m.odds, m.myOdds = chances, nil
		ns.Fire("SESSION_CHANGED")
		if not withMe then return end
		ns.OddsLater(withMe, copies, function(mine)
			if live.mirror ~= m or run ~= oddsRun then return end
			m.myOdds = mine[me]
			ns.Fire("SESSION_CHANGED")
		end)
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
	-- The pity of everyone in the group with some on the item, from the writer's table (6.3).
	local pool = {}
	local _, list = ns.Decode(ns.ReadPool, type(d.pool) == "string" and d.pool or "")
	for _, entry in ipairs(list or {}) do pool[entry[1]] = (entry[2] + 1) * ns.PITY_STEP end
	live.mirror = {
		sid = d.sid, item = d.item, copies = d.copies, greed = d.greed, opened = d.opened,
		instance = type(d.instance) == "string" and d.instance or nil, boss = type(d.boss) == "string" and d.boss or nil,
		state = "open", round = 1, ends = GetTime() + d.secs, duration = d.secs, pool = pool,
		entrants = {}, rounds = { {} }, winners = {}, rejects = {}, passed = {},
	}
	live.observed = {}
	ns.LearnSource(d.item, live.mirror.instance, live.mirror.boss)
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
			m.rejects[#m.rejects + 1] = {
				round = d.round, name = r.name, roll = r.roll, why = r.why,
				low = type(r.low) == "number" and r.low or nil, high = type(r.high) == "number" and r.high or nil,
			}
		else
			if d.round == 1 then
				m.entrants[r.id] = { name = r.name, pity = r.pity, offSpec = r.os or nil, unknownRole = r.unknown or nil }
			end
			m.rounds[d.round] = m.rounds[d.round] or {}
			m.rounds[d.round][r.id] = r.roll
			m.passed[r.id] = nil -- someone who passed and then rolled anyway
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
		entrant.unknownRole = d.unknown or nil
	end
end

function Valid.reroll(d)
	return IsCount(d.round) and type(d.ids) == "table" and IsCount(d.slots) and type(d.secs) == "number"
end
function Mirror.reroll(d, m)
	VerifyRound(m, m.round)
	m.openOdds = m.openOdds or m.odds -- what everyone's chances were before the tie, kept for those out of the reroll
	m.state, m.round, m.slots, m.ends, m.duration = "reroll", d.round, d.slots, GetTime() + d.secs, d.secs
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
	if ns.ReportWins then ns.ReportWins(m, live.writer) end
end

function Valid.cancel()
	return true
end
function Mirror.cancel(_, m)
	m.state, m.ends = "cancelled", nil
end

function Valid.awarded(d)
	return type(d.rev) == "number" and (d.given == nil or type(d.given) == "table") and (d.change == nil or type(d.change) == "string")
		and (d.sigs == nil or type(d.sigs) == "table")
end
function Mirror.awarded(d, m)
	m.state, m.rev, m.given = "awarded", d.rev, d.given
	if ns.AmWriter() then return end
	LogAward(m)
	-- Officers add the result to their table; members their own share to their row, with its new signature (6.3).
	local head = { rev = d.rev, by = type(d.by) == "string" and d.by or "" }
	local changes = d.change and ns.Decode(ns.ReadDiffs, d.change)
	local change = changes and changes[1]
	if change and change.op == "result" then
		m.result = ns.DiffKey(change)
		CheckResult(m, change, head)
		ns.TakeResult(change, d.sigs, head)
	end
end

function Valid.disenchant()
	return true
end
function Mirror.disenchant(d, m)
	m.state, m.ends = d.sell and "kept" or "disenchanted", nil
end

local function StopAutoRoll(m)
	if autoRollTimer then autoRollTimer:Cancel() end
	autoRollTimer = nil
	if m then m.autoRollAt = nil end
end

-- Auto-roll (an option) rolls for you: in a reroll you're in straight away, and in a new roll you can take part in
-- after a few seconds, so there's time to pass. m.autoRollAt is when, for the window's countdown.
local function ScheduleAutoRoll(kind)
	StopAutoRoll(live.mirror)
	local m = live.mirror
	local mode = ns.settings.autoRoll or ns.AUTO_ROLL.OFF
	if not m or not ns.CanRoll() then return end
	local delay
	if kind == "reroll" and mode >= ns.AUTO_ROLL.REROLLS then
		delay = 0
	elseif kind == "open" and mode >= ns.AUTO_ROLL.ALL then
		delay = AUTO_ROLL_DELAY
	end
	if not delay then return end
	if delay > 0 then m.autoRollAt = GetTime() + delay end
	autoRollTimer = C_Timer.NewTimer(delay, function()
		autoRollTimer = nil
		if live.mirror ~= m then return end
		m.autoRollAt = nil
		ns.Roll()
	end)
end

local function Changed(kind)
	RefreshOdds()
	if kind == "open" or kind == "reroll" then ScheduleAutoRoll(kind) end
	-- A roll you can take part in (or are running) opens the window on the Roll tab.
	if (kind == "open" or kind == "reroll") and ns.settings.autoShow and ns.ShowWindow
		and (ns.CanRoll() or (kind == "open" and ns.AmWriter())) then
		ns.ShowWindow("session")
	end
	ns.Fire("ROLL_EVENT", kind, live.mirror)
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
	ns.Capture("emit", kind, data)
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
	StopAutoRoll(live.mirror)
	engine = nil
	if closeTimer then closeTimer:Cancel() end
	if warnTimer then warnTimer:Cancel() end
	if tieTimer then tieTimer:Cancel() end
	if earlyTimer then earlyTimer:Cancel() end
	closeTimer, warnTimer, tieTimer, earlyTimer = nil, nil, nil, nil
	pending, pendingRound = {}, nil
end

local function ScheduleClose(secs)
	if closeTimer then closeTimer:Cancel() end
	closeTimer = C_Timer.NewTimer(secs, function()
		closeTimer = nil
		ns.CloseRound()
	end)
end

-- Whether everyone in the group who can roll in the opening round has rolled or passed, and someone has. Players who
-- are offline don't count; players without the addon do, as they can only roll, so until they do the round runs its
-- time.
local function EveryoneHasRolled(m)
	local rolled = m.rounds[1] or {}
	if not (next(rolled) or next(m.passed)) then return false end
	for _, member in ipairs(ns.GroupMembers()) do
		local id = member.guid
		if not rolled[id] and m.passed[id] ~= 1 and UnitIsConnected(member.unit)
			and ns.MayRollOn(id, m.item, m.greed) then
			return false
		end
	end
	return true
end

-- A reroll ends as soon as every tied player has rolled again or passed; the opening round a moment after everyone
-- who can roll has, or passed.
local function CloseIfAllDone(m)
	if m.state == "reroll" then
		for contender in pairs(m.contenders) do
			if not (m.rounds[m.round] and m.rounds[m.round][contender]) and m.passed[contender] ~= m.round then return end
		end
		return ns.CloseRound()
	end
	if m.state ~= "open" or earlyTimer or not EveryoneHasRolled(m) then return end
	earlyTimer = C_Timer.NewTimer(EARLY_END, function()
		earlyTimer = nil
		if live.mirror == m and m.state == "open" and EveryoneHasRolled(m) then ns.CloseRound() end
	end)
end

-- Someone who hadn't rolled leaving the group, or going offline, can leave everyone else done.
local function RecheckDone()
	local m = live.mirror
	if engine and m and ns.AmWriter() then CloseIfAllDone(m) end
end
ns.Listen("ROSTER_CHANGED", RecheckDone)
ns.On("UNIT_CONNECTION", RecheckDone)

-- Tells a player without the addon why their roll didn't count, once per roll, by whisper (5.3). Players with it,
-- the writer included, see why on their own row on the Roll tab instead (ns.MyRefusal). In test mode on your own,
-- your own refused rolls are whispered to you as well, to try it out.
-- `why` is the refusal's code; a roll in the wrong range comes with the range rolled.
local function WhisperRefusal(m, member, why, low, high)
	if not member or users[member.guid] or not ns.settings.whisperRefusals or not (IsInGroup() or ns.IsTestMode()) then
		return
	end
	if IsInGroup() and member.guid == UnitGUID("player") then return end
	if ns.TestIsPrivate() and member.guid ~= UnitGUID("player") then return end -- test mode keeps to this client
	m.whispered = m.whispered or {}
	if m.whispered[member.guid] then return end
	m.whispered[member.guid] = true
	local reason = why == "range" and CHAT.WHY_RANGE:format(low, high) or CHAT["WHY_" .. why:upper()]
	local text = CHAT.REFUSED:format(ns.ItemLink(m.item), reason)
	-- A roll in the wrong range can still be put right while the roll's open.
	if why == "range" then text = text .. " " .. CHAT.REFUSED_RANGE_HINT end
	ns.Capture("whisper", member.name, text)
	ChatThrottleLib:SendChatMessage("NORMAL", ns.PREFIX_LIVE, text, "WHISPER", nil, member.name)
end

-- A /roll seen by the writer: counted, or refused with a reason everyone can see (a code, so each client can put it
-- in its own words).
local function WriterRoll(name, roll, low, high)
	local m = live.mirror
	if not engine or not m then return end
	local function Refuse(why)
		local range = why == "range"
		QueueRoll({ name = name, roll = roll, why = why, low = range and low or nil, high = range and high or nil })
		WhisperRefusal(m, ns.GroupMember(name), why, low, high)
	end
	if not IsActive(m) then
		if m.state == "decided" and m.closed and GetTime() - m.closed < LATE_GRACE then Refuse("late") end
		return
	end
	if low ~= ns.ROLL_MIN or high ~= ns.ROLL_MAX then return Refuse("range") end
	local member = ns.GroupMember(name)
	if not member then return Refuse("raid") end
	local id, pity, offSpec, guessed = member.guid, nil, nil, nil
	-- Anyone can greed-roll, and greed is for gold, so nobody is off-spec for it (4.8).
	if m.round == 1 then
		if not m.greed and ns.HasWon(id, m.item) then return Refuse("won") end
		if not m.greed and not ns.CanUse(id, m.item) then return Refuse("cantuse") end
		pity = PityIn(m, id)
		if m.greed then offSpec = false else offSpec, guessed = ns.IsOffSpec(id, m.item) end
	end
	local ok, why = engine:AddRoll(id, roll, pity, offSpec)
	if not ok then return Refuse(why) end
	QueueRoll({ id = id, name = member.name, roll = roll, pity = pity, os = offSpec or nil, unknown = guessed or nil })
	CloseIfAllDone(m)
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
			-- Your own /roll, typed or not: the prompt and any auto-roll go now, not once the writer counts it.
			if member.guid == UnitGUID("player") and m.rolledRound ~= m.round then
				m.rolledRound = m.round
				StopAutoRoll(m)
				ns.Fire("SESSION_CHANGED")
			end
		end
	end
	if ns.AmWriter() then WriterRoll(name, roll, low, high) end
end)

-- Players without the addon are whispered, once a night, that the raid uses it and that they can /roll or pass (5.3).
-- Every client with the addon answers a new writer, or asks the writer what's on as it joins, so anyone in the group
-- who hasn't been heard from INTRO_WAIT seconds after the writer takes charge, or after they join, has none. Test mode
-- on your own whispers nobody, as it sends nothing.
local introTimer

local function Introduced()
	local told = ns.saved.introduced or {}
	ns.saved.introduced = told
	local now = GetServerTime()
	for id, at in pairs(told) do
		if now - at > INTRO_AGAIN then told[id] = nil end
	end
	return told, now
end

local function Introduce()
	introTimer = nil
	if not ns.AmWriter() or not IsInGroup() or ns.TestIsPrivate() then return end
	local told, now = Introduced()
	local me = UnitGUID("player")
	for _, member in ipairs(ns.GroupMembers()) do
		local id = member.guid
		if id ~= me and not users[id] and not told[id] and UnitIsConnected(member.unit) then
			told[id] = now
			ns.Capture("whisper", member.name, CHAT.INTRO)
			ChatThrottleLib:SendChatMessage("NORMAL", ns.PREFIX_LIVE, CHAT.INTRO, "WHISPER", nil, member.name)
		end
	end
end

local function IntroduceSoon()
	if introTimer or not ns.AmWriter() then return end
	introTimer = C_Timer.NewTimer(INTRO_WAIT, Introduce)
end
ns.Listen("ROSTER_CHANGED", IntroduceSoon)

-- Takes the writer role (6.2), and takes over a roll already in progress from the mirror.
function ns.ClaimWriter()
	if not IsInGroup() and not ns.IsTestMode() then return ns.Print(L.MSG_NEED_GROUP) end
	if not ns.IsOfficer(ns.PlayerName()) then return ns.Print(L.MSG_WRITER_OFFICERS) end
	if not ns.ledger then return ns.Print(L.MSG_LEDGER_NOT_LOADED) end
	-- Taking over from another writer: the players here were whispered by them, if they needed to be.
	if live.writer and live.writer ~= ns.PlayerName() then
		local told, now = Introduced()
		for _, member in ipairs(ns.GroupMembers()) do told[member.guid] = told[member.guid] or now end
	end
	live.writer = ns.PlayerName()
	ns.MergeChanges()
	SendLive("writer", {})
	IntroduceSoon()
	local m = live.mirror
	if m and (IsActive(m) or m.state == "decided") then
		engine = Rebuild(m, m.state == "decided")
		if IsActive(m) then ScheduleClose(math.max((m.ends or GetTime()) - GetTime(), 5)) end
		Announce(CHAT.TAKEN_OVER:format(MyWriterName(), ns.ItemLink(m.item)))
	else
		Announce(CHAT.RUNNING_ROLLS:format(MyWriterName()))
	end
	rolesSent = nil
	ns.Fire("ROLES_CHANGED")
	ns.RememberRoles()
	ns.InspectRoles()
	ns.Fire("SESSION_CHANGED")
end

-- Where the item dropped: the raid (or dungeon) the writer is in, and the boss last killed there, if any. Recorded
-- with the roll so pity can be grouped by raid and boss.
local lastKill
ns.On("ENCOUNTER_END", function(_, encounterName, _, _, success)
	if success == 1 then lastKill = { boss = encounterName, instance = (GetInstanceInfo()) } end
end)

-- The boss last killed in the instance you're in, if any: who dropped the loot you're looking at.
function ns.LastBoss()
	local instance = GetInstanceInfo()
	return lastKill and lastKill.instance == instance and lastKill.boss or nil
end

-- The boss comes from the loot: a boss's corpse, or trash (Loot.lua); failing that, the boss last killed here.
local function DropSource(item)
	local name, instanceType = GetInstanceInfo()
	if instanceType ~= "raid" and instanceType ~= "party" then return nil end
	local boss = ns.LootBossOf(item)
	if boss == nil then boss = lastKill and lastKill.instance == name and lastKill.boss or nil end
	return name, boss or nil
end

-- The pity of everyone in the group who could roll and has some on the item, packed for the roll's start (6.3).
local function PoolFor(item, greed)
	if greed then return nil end
	local pool = {}
	for _, member in ipairs(ns.GroupMembers()) do
		local id = member.guid
		if id and ns.MayRollOn(id, item) then
			local pity = ns.PityOf(id, item)
			if pity > 0 then pool[#pool + 1] = { id, pity / ns.PITY_STEP - 1 } end
		end
	end
	return pool[1] and ns.EncodePool(item, pool) or nil
end

function ns.StartRoll(item, copies, greed)
	if not ns.AmWriter() then return ns.Print(L.MSG_WRITER_ONLY) end
	if ns.SyncBusy() then return ns.Print(L.MSG_WAIT_SYNC) end
	local m = live.mirror
	if IsActive(m) or (m and m.state == "decided" and m.winners[1]) then
		return ns.Print(L.MSG_FINISH_ROLL)
	end
	copies = copies or 1
	count = count + 1
	local opened = GetServerTime()
	local instance, boss = DropSource(item)
	engine = ns.NewSession(item, copies, greed)
	Emit("open", {
		sid = ("%s:%d:%d"):format(ns.PlayerName(), opened, count),
		item = item, copies = copies, greed = greed or nil, opened = opened, secs = ns.settings.rollTime,
		instance = instance, boss = boss, pool = PoolFor(item, greed),
	})
	local what = copies > 1 and CHAT.COPIES:format(ns.ItemLink(item), copies) or ns.ItemLink(item)
	Announce((greed and CHAT.GREED_ROLL_START or CHAT.ROLL_START):format(what, ns.settings.rollTime), true)
	ScheduleClose(ns.settings.rollTime)
	ns.InspectRoles(true)
	-- A last call a few seconds before the opening round closes, for players without the addon's timer.
	local started = live.mirror
	if warnTimer then warnTimer:Cancel() end
	warnTimer = C_Timer.NewTimer(ns.settings.rollTime - CLOSING_WARNING, function()
		warnTimer = nil
		if live.mirror == started and started.state == "open" and ns.AmWriter() then
			Announce(CHAT.CLOSING:format(CLOSING_WARNING, ns.ItemLink(item)))
		end
	end)
end

-- A tie is announced a moment after its reroll starts, and only if it's still on: when every tied player rerolls
-- straight away (auto-roll), raid chat doesn't hear tie after tie, just the result. The time left is as it is then.
local function AnnounceTieSoon(m, tied, winners, slots)
	if tieTimer then tieTimer:Cancel() end
	local round = m.round
	tieTimer = C_Timer.NewTimer(TIE_QUIET, function()
		tieTimer = nil
		if live.mirror ~= m or m.state ~= "reroll" or m.round ~= round then return end
		local secs = math.max(math.ceil((m.ends or GetTime()) - GetTime()), 1)
		-- With several copies some may be won already, and the tie is for the rest.
		local what = ns.ItemLink(m.item)
		if winners[1] then
			Announce((#winners > 1 and CHAT.WIN or CHAT.WINS):format(NameList(winners), what))
			what = slots > 1 and CHAT.LAST_COPIES:format(slots, what) or CHAT.LAST_COPY:format(what)
		end
		Announce(CHAT.TIE:format(what, NameList(tied), secs), true)
	end)
end

function ns.CloseRound()
	local m = live.mirror
	if not ns.AmWriter() or not engine or not IsActive(m) then return end
	if closeTimer then closeTimer:Cancel() end
	if earlyTimer then earlyTimer:Cancel() end
	closeTimer, earlyTimer = nil, nil
	Flush()
	local result, tied = engine:CloseRound()
	if result == "reroll" then
		local secs = ns.settings.rerollTime
		Emit("reroll", {
			sid = m.sid, round = #engine.rounds, ids = tied, slots = engine.slots,
			winners = ns.Copy(engine.winners), secs = secs,
		})
		AnnounceTieSoon(m, tied, ns.Copy(engine.winners), engine.slots)
		ScheduleClose(secs)
		return
	end
	Emit("decided", { sid = m.sid, winners = ns.Copy(engine.winners) })
	if not engine.winners[1] then
		Announce(CHAT.NO_ONE_ROLLED:format(ns.ItemLink(m.item)), true)
		engine = nil
		return
	end
	Announce(CHAT.GOES_TO:format(ns.ItemLink(m.item), NameList(engine.winners)), true)
	for _, id in ipairs(engine.winners) do Announce(Breakdown(m, id)) end
	if ns.settings.autoAward then ns.Award() end
end

-- Hands out the item and records the result, which is when the losers gain pity (4.1): the writer adds it to its table
-- as a change, and tells the group with the new signatures of the sub-rows it changed (6.3). A greed roll changes no
-- pity (4.8).
function ns.Award()
	local m = live.mirror
	if not ns.AmWriter() or not engine or not engine.done or not m or m.state ~= "decided" then
		return ns.Print(L.MSG_NOTHING_TO_AWARD)
	end
	local winners = ns.Copy(engine.winners)
	local change, sigs
	if not m.greed then
		local won, losers = {}, {}
		for _, id in ipairs(winners) do won[id] = true end
		for id in pairs(engine.entrants) do
			if not won[id] then losers[#losers + 1] = id end
		end
		table.sort(losers)
		change, sigs = ns.RecordResult(m.item, m.instance, m.boss, losers, winners)
		if not change then return ns.Warn(L.WARN_AWARD_FAILED:format(L.LEDGER_NOT_OFFICER)) end
	end
	LogAward(m)
	local given = ns.GiveLoot(m.item, winners)
	engine = nil
	local head = ns.Head()
	Emit("awarded", {
		sid = m.sid, rev = head.rev, by = head.by, given = given[1] and given or nil,
		change = change and ns.EncodeDiffs({ change }) or nil, sigs = sigs,
	})
end

-- A BoP item no one rolled on is disenchanted, and a BoE no one greed-rolled on is kept to sell (it's worth more on
-- the auction house). Nothing goes in the ledger, as no one rolled. The master looter takes it, to disenchant, hand to
-- an enchanter, or sell.
local function TakeUnwanted(sell)
	local m = live.mirror
	if not ns.AmWriter() or not m or m.state ~= "decided" or m.winners[1] then
		return ns.Print(sell and L.MSG_ONLY_SELL or L.MSG_ONLY_DISENCHANT)
	end
	engine = nil
	if IsMasterLooter() then
		local me = {}
		for i = 1, m.copies do me[i] = UnitGUID("player") end
		ns.GiveLoot(m.item, me, true)
	end
	Emit("disenchant", { sid = m.sid, sell = sell or nil })
	Announce((sell and CHAT.SOLD or CHAT.DISENCHANTED):format(ns.ItemLink(m.item)))
end

function ns.Disenchant()
	TakeUnwanted(false)
end

function ns.KeepToSell()
	TakeUnwanted(true)
end

function ns.CancelRoll()
	local m = live.mirror
	if not ns.AmWriter() or not m or not (IsActive(m) or m.state == "decided") then return end
	StopWriting()
	Emit("cancel", { sid = m.sid })
	Announce(CHAT.CANCELLED:format(ns.ItemLink(m.item)))
end

-- The writer's correction of a roll's off-spec flag, before the first round closes.
function ns.ToggleOffSpec(id)
	local m = live.mirror
	if not ns.AmWriter() or not engine or not m or m.state ~= "open" or not m.entrants[id] then return end
	if m.greed or ns.ForEveryone(m.item) then return end -- nobody is off-spec for it
	local offSpec = not m.entrants[id].offSpec
	if engine:SetOffSpec(id, offSpec) then Emit("os", { sid = m.sid, id = id, os = offSpec or nil }) end
end

-- An officer's say on which roles an item is for (4.6), kept in the ledger's item table so every client
-- agrees and later drops use it. If the writer is running an open roll for the item, everyone's off-spec flag follows
-- it. No role ticked means any role, as every role ticked does.
function ns.SetItemRoles(item, suits)
	if not ns.IsOfficer(ns.PlayerName()) then return end
	local bits = 0
	for _, role in ipairs(ns.ROLE_ORDER) do
		if suits[role] then bits = bits + ns.ROLE_BITS[role] end
	end
	local ok, err = ns.RecordChange(ns.NewChange({ op = "itemroles", item = item, roles = bits ~= 0 and bits or 7 }))
	if not ok then return ns.Print(L.MSG_ROLES_FAILED:format(err)) end
	local m = live.mirror
	if not (ns.AmWriter() and engine and m and m.state == "open" and m.item == item and not m.greed) then return end
	for id, entrant in pairs(m.entrants) do
		local offSpec = ns.IsOffSpec(id, item)
		if offSpec ~= nil and offSpec ~= (entrant.offSpec or false) and engine:SetOffSpec(id, offSpec) then
			Emit("os", { sid = m.sid, id = id, os = offSpec or nil })
		end
	end
end

-- A role found while a roll's first round is open (an inspect answering) settles the off-spec flag of a player whose
-- role wasn't known when they rolled.
-- An officer's say on a role settles it for anyone who has rolled, whether it was known or not.
ns.Listen("ROLE_FOUND", function(guid, settled)
	local m = live.mirror
	if not (ns.AmWriter() and engine and m and m.state == "open" and not m.greed) then return end
	local entrant = m.entrants[guid]
	if not (entrant and (entrant.unknownRole or settled)) then return end
	local offSpec, guessed = ns.IsOffSpec(guid, m.item)
	if offSpec ~= nil and engine:SetOffSpec(guid, offSpec) then
		Emit("os", { sid = m.sid, id = guid, os = offSpec or nil, unknown = guessed or nil })
	end
end)

-- Roles (Roles.lua) -----------------------------------------------------------------------------------------------

-- An officer's say on a raider's role, from the Raid tab, for the whole group; nil goes back to working it out.
function ns.SetRole(guid, role)
	if not ns.IsOfficer(ns.PlayerName()) then return end
	if ns.ApplyRole(guid, role, ns.PlayerName()) then SendLive("setrole", { id = guid, role = role }) end
end

ns.Receive(LIVE, "setrole", function(d, sender)
	if type(d) ~= "table" or type(d.id) ~= "string" or not ns.IsOfficer(sender) then return end
	ns.ApplyRole(d.id, d.role, ns.DisplayName(sender))
end)

-- An officer's inspect from the Raid tab goes to the writer, whose view of the roles everyone sees.
function ns.TellInspected(guid, role, why)
	if live.writer then SendLive("inspected", { id = guid, role = role, why = why }, live.writer) end
end

ns.Receive(LIVE, "inspected", function(d, sender)
	if type(d) ~= "table" or type(d.id) ~= "string" or not ns.IsOfficer(sender) or not ns.AmWriter() then return end
	if d.role then ns.ApplyInspect(d.id, d.role, true) else ns.InspectFailed(d.id, d.why) end
end)

-- The writer tells the group the roles it knows (it inspects players, so it knows most), a moment after they change
-- and only if they did, so the Raid tab shows the same for every officer.
local ROLES_DELAY = 1
local rolesTimer
ns.Listen("ROLES_CHANGED", function()
	if rolesTimer or not ns.AmWriter() then return end
	rolesTimer = C_Timer.NewTimer(ROLES_DELAY, function()
		rolesTimer = nil
		if not ns.AmWriter() then return end
		local map = ns.RoleMap()
		local text = ns.Serialize(map)
		if text == rolesSent then return end
		rolesSent = text
		SendLive("roles", { r = map })
	end)
end)

ns.Receive(LIVE, "roles", function(d, sender)
	if type(d) == "table" and live.writer and ns.SameName(sender, live.writer) then ns.SetWriterRoles(d.r) end
end)

-- Why you can't take part in the roll that's on, if you can't, for the window: nottied (it's a reroll you're not
-- in), won or class.
function ns.WhyCantRoll()
	local m = live.mirror
	if not IsActive(m) then return nil end
	local me = UnitGUID("player")
	if m.state == "reroll" then
		return not m.contenders[me] and "nottied" or nil
	end
	if m.greed then return nil end
	if ns.HasWon(me, m.item) then return "won" end
	if not ns.CanUse(me, m.item) then return "class" end
	return nil
end

-- Your own latest /roll the writer didn't count in the round the roll is on, if any, for the window: the refusal
-- ({roll, why, low, high}, why being a code), and the round it was in.
function ns.MyRefusal()
	local m = live.mirror
	if not m then return nil end
	local me = UnitGUID("player")
	for i = #m.rejects, 1, -1 do
		local reject = m.rejects[i]
		local member = reject.round == m.round and ns.GroupMember(reject.name)
		if member and member.guid == me then return reject end
	end
	return nil
end

-- Whether this player can roll right now: a roll or their reroll is open, and they haven't rolled or passed in it.
function ns.CanRoll()
	local m = live.mirror
	if not IsActive(m) or m.rolledRound == m.round then return false end
	local me = UnitGUID("player")
	if m.rounds[m.round] and m.rounds[m.round][me] then return false end
	if m.passed[me] == m.round then return false end
	if m.state == "reroll" then return m.contenders[me] == true end
	return ns.MayRollOn(me, m.item, m.greed)
end

-- Whether a player may roll on an item at all: their class can use it (4.5) and they haven't won it (4.4). Anyone
-- may greed-roll (4.8).
function ns.MayRollOn(id, item, greed)
	if greed then return true end
	if ns.HasWon(id, item) then return false end
	return ns.CanUse(id, item)
end

-- The window's roll button: a /roll 1-100, which the writer counts like any other.
function ns.Roll()
	if not ns.CanRoll() then return end
	live.mirror.rolledRound = live.mirror.round
	StopAutoRoll(live.mirror)
	RandomRoll(ns.ROLL_MIN, ns.ROLL_MAX)
	ns.Fire("SESSION_CHANGED")
end

-- Whether a player can pass in this round: it's on, they haven't rolled in it, and in a reroll they're tied.
local function MayPass(m, id, round)
	if not IsActive(m) or round ~= m.round or (m.rounds[m.round] and m.rounds[m.round][id]) then return false end
	return m.state ~= "reroll" or m.contenders[id] == true
end

-- Passing: you won't roll in this round. It changes nothing in the ledger (not rolling never does, 4.1), but it takes
-- you out of everyone's odds, ends the round sooner, and stops auto-roll. A /roll afterwards still counts.
local function Passed(m, id, round)
	if not MayPass(m, id, round) then return end
	m.passed[id] = round
	if id == UnitGUID("player") then StopAutoRoll(m) end
	RefreshOdds()
	ns.Fire("SESSION_CHANGED")
	if ns.AmWriter() then CloseIfAllDone(m) end
end

function ns.Pass()
	local m = live.mirror
	if not ns.CanRoll() then return end
	SendLive("pass", { sid = m.sid, round = m.round })
	Passed(m, UnitGUID("player"), m.round)
end

ns.Receive(LIVE, "pass", function(d, sender)
	local m = live.mirror
	local member = ns.GroupMember(sender)
	if type(d) ~= "table" or not m or d.sid ~= m.sid or not member or type(d.round) ~= "number" then return end
	Passed(m, member.guid, d.round)
end)

-- Players without the addon pass by typing exactly "pass" (any case) in raid chat (party chat in a party), or whispering
-- it to the writer; anyone else can too. Only the writer takes it, as it alone knows who can roll, and tells the group.
local CHAT_PASS = "pass"

local function ChatPass(text, sender)
	local m = live.mirror
	if not (engine and m and ns.AmWriter() and canaccessvalue(text) and canaccessvalue(sender)) then return end
	if type(text) ~= "string" or strtrim(text):lower() ~= CHAT_PASS then return end
	local member = ns.GroupMember(sender)
	if not member or m.passed[member.guid] == m.round or not MayPass(m, member.guid, m.round) then return end
	if m.state == "open" and not ns.MayRollOn(member.guid, m.item, m.greed) then return end
	SendLive("passed", { sid = m.sid, round = m.round, id = member.guid })
	Passed(m, member.guid, m.round)
end
for _, event in ipairs({ "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_WHISPER" }) do
	ns.On(event, ChatPass)
end

ns.Receive(LIVE, "passed", function(d, sender)
	local m = live.mirror
	if type(d) ~= "table" or not m or d.sid ~= m.sid or type(d.id) ~= "string" or type(d.round) ~= "number" then return end
	if live.writer and ns.SameName(sender, live.writer) then Passed(m, d.id, d.round) end
end)

-- For the test commands: counts a roll from a made-up player, as if the writer had seen their /roll. `unknown`: the
-- off-spec flag comes from a fallback role.
function ns.CountTestRoll(id, name, roll, pity, offSpec, unknown)
	local m = live.mirror
	if not ns.AmWriter() or not engine or not IsActive(m) then return false, "no roll is open" end
	if m.round > 1 then pity = nil end
	local ok, why = engine:AddRoll(id, roll, pity, offSpec)
	if not ok then return false, why end
	QueueRoll({ id = id, name = name, roll = roll, pity = pity, os = offSpec or nil, unknown = unknown or nil })
	CloseIfAllDone(m)
	return true
end

-- Test mode turning off (TestCommands.lua): stops being the writer without telling anyone, and drops the roll, so
-- nothing run in test mode carries on in a real group.
function ns.StopTestWriting()
	if not ns.AmWriter() then return end
	StopWriting()
	live.writer, live.mirror = nil, nil
	ns.Fire("SESSION_CHANGED")
end

-- Handover and late joiners ---------------------------------------------------------------------------------------

local toldRole -- the role this client last told the writer

-- What this client says to the writer: the role its talents show, or why they don't settle one; and, for a member,
-- what its own row holds, so the writer can send back anything that differs (the row check, 6.3).
local function MyRoleMessage()
	local role, why = ns.MyRole()
	local message = { role = role, why = (why == "nocapstone" or why == "ambiguous") and why or nil }
	if ns.ledger and not ns.HoldsTable() then
		local me = UnitGUID("player")
		message.check = ns.EncodeRowCheck(me, ns.RowsOf(me))
	end
	return message
end

-- The writer checking a raider's row (6.3).
local function CheckRaiderRows(d, sender)
	local member = ns.AmWriter() and type(d.check) == "string" and ns.GroupMember(sender)
	if member then ns.CheckRows(member.guid, d.check) end
end

ns.Receive(LIVE, "writer", function(_, sender)
	if not ns.IsOfficer(sender) then return end
	if ns.AmWriter() then
		StopWriting()
		ns.Print(L.MSG_WRITER_TAKEN:format(sender))
	end
	live.writer = sender
	local said = MyRoleMessage()
	toldRole = said.role or said.why
	SendLive("here", said, sender)
	ns.Fire("SESSION_CHANGED")
end)

ns.Receive(LIVE, "here", function(d, sender)
	if type(d) ~= "table" then return end
	ns.ToldRole(sender, d.role, d.why)
	CheckRaiderRows(d, sender)
end)

-- A new spec or talents can mean a new role; the writer hears of it, though a role already used for a roll stays.
local function RetellRole()
	local said = MyRoleMessage()
	if (said.role or said.why) == toldRole or not live.writer or ns.AmWriter() then return end
	toldRole = said.role or said.why
	SendLive("here", said, live.writer)
end
ns.On("PLAYER_TALENT_UPDATE", RetellRole)
ns.On("ACTIVE_TALENT_GROUP_CHANGED", RetellRole)

-- Whoever sends the writer anything has the addon: a reply to a new writer, a query, a pass.
ns.OnMessage(LIVE, function(sender)
	local member = ns.GroupMember(sender)
	if member then users[member.guid] = true end
end)

ns.Receive(LIVE, "query", function(d, sender)
	if type(d) == "table" then
		ns.ToldRole(sender, d.role, d.why)
		CheckRaiderRows(d, sender)
	end
	if not ns.AmWriter() then return end
	local m = live.mirror and ns.Copy(live.mirror)
	if m then m.odds, m.myOdds, m.ends, m.autoRollAt, m.rolledRound = nil, nil, nil, nil, nil end
	SendLive("state", {
		mirror = m, left = live.mirror and live.mirror.ends and live.mirror.ends - GetTime(), loot = ns.Copy(ns.loot),
		roles = ns.RoleMap(), head = ns.Head() and { rev = ns.Head().rev, by = ns.Head().by } or nil,
	}, sender)
end)

ns.Receive(LIVE, "state", function(d, sender)
	if type(d) ~= "table" or not ns.IsOfficer(sender) then return end
	live.writer = sender
	ns.SetWriterRoles(d.roles)
	local m = d.mirror
	if type(m) == "table" and type(m.sid) == "string" and type(m.entrants) == "table" and type(m.rounds) == "table" then
		m.partial = true
		m.passed = type(m.passed) == "table" and m.passed or {}
		m.ends = type(d.left) == "number" and GetTime() + d.left or nil
		live.mirror, live.observed = m, {}
	end
	ns.RestoreLoot(d.loot)
	local head = d.head
	if ns.ledger and not ns.HoldsTable() and type(head) == "table" and type(head.rev) == "number" then
		ns.ledger.data.head.rev, ns.ledger.data.head.by = head.rev, type(head.by) == "string" and head.by or ""
	end
	Changed("state")
end)

ns.On("GROUP_ROSTER_UPDATE", function()
	if not IsInGroup() and not ns.IsTestMode() then
		StopWriting()
		ns.ForgetTaken()
		live.writer, live.mirror, live.observed, queried = nil, nil, {}, false
	else
		if live.writer and not ns.GroupMember(live.writer) then
			ns.Print(L.MSG_WRITER_LEFT:format(live.writer))
			live.writer = nil
		end
		if not queried then
			queried = true
			SendLive("query", MyRoleMessage())
		end
	end
	ns.Fire("SESSION_CHANGED")
end)

-- Whether the writer refused the player's roll in this round.
local function RefusedThisRound(m, id)
	for _, reject in ipairs(m.rejects) do
		local member = reject.round == m.round and ns.GroupMember(reject.name)
		if member and member.guid == id then return true end
	end
	return false
end

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
		row.name, row.pity, row.offSpec, row.unknownRole = entrant.name or row.name, entrant.pity, entrant.offSpec, entrant.unknownRole
	end
	for r = 1, #m.rounds do
		for id, roll in pairs(m.rounds[r]) do
			local row = Row(id)
			row.roll, row.round = roll, r
		end
	end
	-- While a reroll is on, the tied players' earlier rolls stay until they roll again, marked as from before the tie,
	-- so the tie can still be seen but it's clear which numbers are new.
	if m.state == "reroll" then
		for id in pairs(m.contenders) do
			local row = Row(id)
			if row.roll and row.round ~= m.round then row.stale = true end
		end
	end
	-- Passes: in an opening round, by anyone; in a reroll, by those tied in this round.
	for id, round in pairs(m.passed) do
		if round == m.round or not (m.contenders and m.contenders[id]) then Row(id).passed = true end
	end
	-- While the opening round's on, everyone in the group who could roll is listed, the ones yet to roll at the pity
	-- known for them (none, if it isn't).
	if m.state == "open" then
		for _, member in ipairs(ns.GroupMembers()) do
			if member.guid and ns.MayRollOn(member.guid, m.item, m.greed) then Row(member.guid) end
		end
	end
	-- Your own /roll shows as soon as the game says what you rolled, worked out as the writer will count it, rather than
	-- half a second later when the writer's count arrives, so your row goes straight to its place. Between clicking and
	-- the game's answer, the row keeps its place at the top.
	local me = UnitGUID("player")
	local eligible = m.state == "reroll" and m.contenders[me] or m.state == "open" and ns.MayRollOn(me, m.item, m.greed)
	if eligible and not (m.rounds[m.round] and m.rounds[m.round][me]) and not RefusedThisRound(m, me) then
		local seen = live.observed[me] and live.observed[me][m.round]
		if seen then
			local row = Row(me)
			row.roll, row.round, row.stale, row.passed = seen, m.round, nil, nil
			if not m.entrants[me] and not m.greed then
				local offSpec, guessed = ns.IsOffSpec(me, m.item)
				row.offSpec, row.unknownRole = offSpec or nil, guessed or nil
			end
		elseif m.rolledRound == m.round then
			Row(me).rolling = true
		end
	end
	-- Odds from before any reroll, then the reroll's own for the players in it.
	for id, chance in pairs(m.openOdds or {}) do Row(id).odds = chance end
	for id, chance in pairs(m.odds or {}) do
		if not m.contenders or m.contenders[id] then Row(id).odds = chance end
	end
	for _, id in ipairs(m.winners or {}) do Row(id).winner = true end
	for _, row in ipairs(rows) do
		if not row.pity then row.pity = PityIn(m, row.id) end
		if row.roll then row.total = ns.EffectiveRoll(row.roll, ns.Bonus(row.pity or 0, row.offSpec)) end
		row.contender = m.contenders and m.contenders[row.id] or nil
		if row.passed then row.odds = nil end
	end
	-- Your own row, at the top until you roll, is where the window's roll prompt goes, with your chance if you roll.
	if ns.CanRoll() then
		local row = Row(UnitGUID("player"))
		row.prompt = true
		row.odds = row.odds or m.myOdds
		row.autoRollAt = m.autoRollAt
		if not row.pity then row.pity = PityIn(m, row.id) end
	end
	table.sort(rows, function(a, b)
		local aTop, bTop = a.prompt or a.rolling or false, b.prompt or b.rolling or false
		if aTop ~= bTop then return aTop end
		-- The players in a reroll stay in their own section above everyone else, during it and after.
		if m.contenders and (a.contender or false) ~= (b.contender or false) then return a.contender == true end
		if (a.passed or false) ~= (b.passed or false) then return b.passed == true end
		if (a.stale or false) ~= (b.stale or false) then return b.stale == true end
		if (a.winner or false) ~= (b.winner or false) then return a.winner == true end
		if (a.total or -1000) ~= (b.total or -1000) then return (a.total or -1000) > (b.total or -1000) end
		if (a.odds or 0) ~= (b.odds or 0) then return (a.odds or 0) > (b.odds or 0) end
		return a.name < b.name
	end)
	return rows
end
