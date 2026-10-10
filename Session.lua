local _, ns = ...

-- Live rolls (5.1). The writer runs the real roll and tells the group what happens. Everyone, the writer included,
-- keeps a mirror of the roll to show, and everyone else checks it against the /roll messages they saw and their own
-- copy of the ledger (6.1). Messages on the live prefix, all from the writer except query:
--
--   writer  {}                                       an officer claiming the writer role
--   open    {sid, item, copies, greed, opened, secs, instance, boss} a roll starts (and where the item dropped)
--   rolls   {sid, round, list}                       rolls counted ({id, name, roll, pity, os}) or refused ({name, roll, why})
--   os      {sid, id, os}                            the writer corrected an off-spec flag
--   reroll  {sid, round, ids, slots, winners, secs}  a tie that needs rolling off
--   decided {sid, winners}
--   cancel  {sid}
--   awarded {sid, rev, given}                        recorded in the ledger as revision `rev`; `given` got theirs by
--                                                    master loot, so there's nothing to trade them
--   disenchant {sid, sell}                           no one rolled on a BoP item, so it's to be disenchanted; or with
--                                                    `sell`, no one greed-rolled on a BoE, so it's kept to be sold
--   pass    {sid, round}                             anyone: they won't roll in this round
--   query   {}                                       anyone: who's the writer, and what's happening?
--   state   {mirror, left}                           the writer's reply
--   here    {}                                       anyone, to a new writer: this player has the addon

local LIVE = ns.PREFIX_LIVE
local FLUSH_DELAY = 0.5
local LATE_GRACE = 10 -- seconds after a roll is decided that late /rolls are still answered with a refusal
local ROLL_LOCK = 3 -- rerolls in a row after which the raid hears the players are roll-locked
local AUTO_ROLL_DELAY = 5 -- seconds auto-roll waits in a new roll, so there's time to pass
local CLOSING_WARNING = 5 -- seconds before a roll closes that raid chat is told, for players without the addon
local TIE_QUIET = 1.5 -- seconds a tie waits before raid chat hears of it, so instant rerolls don't fill raid chat

local live = { observed = {} }
ns.live = live

local engine -- the writer's ns.NewSession behind the mirror
local closeTimer
local pending, pendingRound, flushing = {}, nil, false
local count = 0
local queried = false
local autoRollTimer, warnTimer, tieTimer
-- Players the writer knows have the addon (by GUID), who are told why a roll didn't count in the window rather than
-- by whisper.
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

-- Test mode on your own (TestCommands.lua, temporary): shows what the raid would see, as if you led it. Each line
-- goes in your chat in its channel's colour, and headlines also appear in the middle of the screen like raid warnings.
local function Preview(text, channel)
	local line = ("[%s] %s: %s"):format(CHANNEL_LABELS[channel], ns.PlayerName(), text)
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
	text = text:gsub("^%l", string.upper)
	local channel = grouped and GroupChannel() or "RAID"
	local canWarn = not grouped
		or IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") or IsEveryoneAssistant())
	if headline and ns.settings.raidWarning and canWarn then channel = "RAID_WARNING" end
	ns.Capture("announce", channel, text)
	if not grouped then return Preview(text, channel) end
	ChatThrottleLib:SendChatMessage("NORMAL", ns.PREFIX_LIVE, text, channel)
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
	if entrant.pity > 0 then text = ("%s + %d pity"):format(text, entrant.pity) end
	if entrant.offSpec then text = ("%s - %d off-spec"):format(text, -ns.OFFSPEC_MODIFIER) end
	local bonus = ns.Bonus(entrant.pity, entrant.offSpec)
	local total = ns.EffectiveRoll(roll, bonus)
	if entrant.pity > 0 or entrant.offSpec then
		text = ("%s = %d"):format(text, total)
		if total < roll + bonus then text = text .. " (max)" end
	end
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
		local state = ns.ledger and ns.ledger.state
		if state then
			for _, member in ipairs(ns.GroupMembers()) do
				local id = member.guid
				if not m.entrants[id] and not m.passed[id] and ns.MayRollOn(id, m.item, m.greed) then
					local pity = state:GetPity(id, m.item, m.greed, m.opened)
					if pity > 0 then Add(id, pity) end
				end
			end
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
		withMe = { { id = me, pity = ns.ledger and ns.ledger.state:GetPity(me, m.item, m.greed, m.opened) or 0,
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
	live.mirror = {
		sid = d.sid, item = d.item, copies = d.copies, greed = d.greed, opened = d.opened,
		instance = type(d.instance) == "string" and d.instance or nil, boss = type(d.boss) == "string" and d.boss or nil,
		state = "open", round = 1, ends = GetTime() + d.secs, duration = d.secs,
		entrants = {}, rounds = { {} }, winners = {}, rejects = {}, passed = {},
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
		entrant.unknownRole = nil
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
end

function Valid.cancel()
	return true
end
function Mirror.cancel(_, m)
	m.state, m.ends = "cancelled", nil
end

function Valid.awarded(d)
	return type(d.rev) == "number" and (d.given == nil or type(d.given) == "table")
end
function Mirror.awarded(d, m)
	m.state, m.rev, m.given = "awarded", d.rev, d.given
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
	closeTimer, warnTimer, tieTimer = nil, nil, nil
	pending, pendingRound = {}, nil
end

local function ScheduleClose(secs)
	if closeTimer then closeTimer:Cancel() end
	closeTimer = C_Timer.NewTimer(secs, function()
		closeTimer = nil
		ns.CloseRound()
	end)
end

-- A reroll ends as soon as every tied player has rolled again or passed.
local function CloseIfAllRerolled(m)
	if m.state ~= "reroll" then return end
	for contender in pairs(m.contenders) do
		if not (m.rounds[m.round] and m.rounds[m.round][contender]) and m.passed[contender] ~= m.round then return end
	end
	ns.CloseRound()
end

-- Tells a player without the addon why their roll didn't count, once per roll, by whisper (5.3). Players with it see
-- the reason in the window. In test mode on your own, your own refused rolls are whispered to you, to try it out.
local function WhisperRefusal(m, member, why)
	if not member or users[member.guid] or not ns.settings.announce or not (IsInGroup() or ns.IsTestMode()) then return end
	m.whispered = m.whispered or {}
	if m.whispered[member.guid] then return end
	m.whispered[member.guid] = true
	local text = ("Your roll for %s didn't count: %s."):format(ns.ItemLink(m.item), why)
	-- A roll in the wrong range can still be put right while the roll's open.
	if why:find("^rolled ") then text = text .. " Type /roll 100 instead." end
	ns.Capture("whisper", member.name, text)
	ChatThrottleLib:SendChatMessage("NORMAL", ns.PREFIX_LIVE, text, "WHISPER", nil, member.name)
end

-- A /roll seen by the writer: counted, or refused with a reason everyone can see.
local function WriterRoll(name, roll, low, high)
	local m = live.mirror
	if not engine or not m then return end
	local function Refuse(why)
		QueueRoll({ name = name, roll = roll, why = why })
		WhisperRefusal(m, ns.GroupMember(name), why)
	end
	if not IsActive(m) then
		if m.state == "decided" and m.closed and GetTime() - m.closed < LATE_GRACE then Refuse("too late") end
		return
	end
	if low ~= ns.ROLL_MIN or high ~= ns.ROLL_MAX then return Refuse(("rolled %d-%d"):format(low, high)) end
	local member = ns.GroupMember(name)
	if not member then return Refuse("not in the group") end
	local id, pity, offSpec = member.guid, nil, nil
	-- Anyone can greed-roll, and greed is for gold, so nobody is off-spec for it (4.8).
	if m.round == 1 then
		local state = ns.ledger.state
		if not m.greed and state:HasWon(id, m.item) then return Refuse("already won this item") end
		if not m.greed and not ns.CanUse(id, m.item) then return Refuse("can't use this item") end
		pity = state:GetPity(id, m.item, m.greed, m.opened)
		if m.greed then offSpec = false else offSpec = ns.IsOffSpec(id, m.item) end
	end
	local ok, why = engine:AddRoll(id, roll, pity, offSpec)
	if not ok then return Refuse(why) end
	QueueRoll({ id = id, name = member.name, roll = roll, pity = pity, os = offSpec or nil, unknown = m.round == 1 and offSpec == nil or nil })
	CloseIfAllRerolled(m)
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

-- Takes the writer role (6.2), and takes over a roll already in progress from the mirror.
function ns.ClaimWriter()
	if not IsInGroup() and not ns.IsTestMode() then return ns.Print("You need to be in a group.") end
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

local function DropSource()
	local name, instanceType = GetInstanceInfo()
	if instanceType ~= "raid" and instanceType ~= "party" then return nil end
	return name, lastKill and lastKill.instance == name and lastKill.boss or nil
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
	local instance, boss = DropSource()
	engine = ns.NewSession(item, copies, greed)
	Emit("open", {
		sid = ("%s:%d:%d"):format(ns.PlayerName(), opened, count),
		item = item, copies = copies, greed = greed or nil, opened = opened, secs = ns.settings.rollTime,
		instance = instance, boss = boss,
	})
	local what = copies > 1 and ("%s (%d copies)"):format(ns.ItemLink(item), copies) or ns.ItemLink(item)
	Announce(("%sroll for %s: /roll now (%ds)."):format(greed and "greed " or "", what, ns.settings.rollTime), true)
	ScheduleClose(ns.settings.rollTime)
	-- A last call a few seconds before the opening round closes, for players without the addon's timer.
	local started = live.mirror
	if warnTimer then warnTimer:Cancel() end
	warnTimer = C_Timer.NewTimer(ns.settings.rollTime - CLOSING_WARNING, function()
		warnTimer = nil
		if live.mirror == started and started.state == "open" and ns.AmWriter() then
			Announce(("%d seconds left to /roll for %s."):format(CLOSING_WARNING, ns.ItemLink(item)))
		end
	end)
end

-- A tie is announced a moment after its reroll starts, and only if it's still on: when every tied player rerolls
-- straight away (auto-roll), raid chat doesn't hear tie after tie, just the result. The time left is as it is then.
local function AnnounceTieSoon(m, tied, winners, slots, rerolls)
	if tieTimer then tieTimer:Cancel() end
	local round = m.round
	tieTimer = C_Timer.NewTimer(TIE_QUIET, function()
		tieTimer = nil
		if live.mirror ~= m or m.state ~= "reroll" or m.round ~= round then return end
		local secs = math.max(math.ceil((m.ends or GetTime()) - GetTime()), 1)
		-- With several copies some may be won already, and the tie is for the rest.
		local what = ns.ItemLink(m.item)
		if winners[1] then
			Announce(("%s %s %s."):format(NameList(winners), #winners > 1 and "win" or "wins", what))
			what = slots > 1 and ("the last %d copies of %s"):format(slots, what) or ("the last copy of " .. what)
		end
		-- Players with high pity can tie at 100 again and again; from the fourth reroll in a row, that's worth a cheer.
		if rerolls > ROLL_LOCK then
			Announce(("roll-locked! Reroll %d for %s between %s: /roll again (%ds)."):format(rerolls, what,
				NameList(tied), secs), true)
		else
			Announce(("tie for %s between %s: /roll again (%ds)."):format(what, NameList(tied), secs), true)
		end
	end)
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
		AnnounceTieSoon(m, tied, ns.Copy(engine.winners), engine.slots, #engine.rounds - 1)
		ScheduleClose(secs)
		return
	end
	Emit("decided", { sid = m.sid, winners = ns.Copy(engine.winners) })
	if not engine.winners[1] then
		Announce(("no one rolled for %s."):format(ns.ItemLink(m.item)), true)
		engine = nil
		return
	end
	Announce(("%s goes to %s."):format(ns.ItemLink(m.item), NameList(engine.winners)), true)
	for _, id in ipairs(engine.winners) do Announce(Breakdown(m, id)) end
	if ns.settings.autoAward then ns.Award() end
end

-- Records the roll in the ledger, which is when the losers gain pity (4.1), and hands out the item.
function ns.Award()
	local m = live.mirror
	if not ns.AmWriter() or not engine or not engine.done or not m or m.state ~= "decided" then
		return ns.Print("There's no decided roll to award.")
	end
	local entry = engine:Record()
	entry.time, entry.by, entry.sid = m.opened, ns.PlayerName(), m.sid
	entry.instance, entry.boss = m.instance, m.boss
	for id, entrant in pairs(entry.entrants) do entrant.name = m.entrants[id] and m.entrants[id].name end
	local ok, err = ns.AppendEntry(entry)
	if not ok then return ns.Warn("The award couldn't be recorded: " .. err .. ".") end
	local given = ns.GiveLoot(m.item, engine.winners)
	engine = nil
	Emit("awarded", { sid = m.sid, rev = entry.rev, given = given[1] and given or nil })
end

-- A BoP item no one rolled on is disenchanted, and a BoE no one greed-rolled on is kept to sell (it's worth more on
-- the auction house). Nothing goes in the ledger, as no one rolled. The master looter takes it, to disenchant, hand to
-- an enchanter, or sell.
local function TakeUnwanted(sell)
	local m = live.mirror
	if not ns.AmWriter() or not m or m.state ~= "decided" or m.winners[1] then
		return ns.Print(sell and "Only a BoE no one greed-rolled on can be kept to sell."
			or "Only an item no one rolled on can be disenchanted.")
	end
	engine = nil
	if IsMasterLooter() then
		local me = {}
		for i = 1, m.copies do me[i] = UnitGUID("player") end
		ns.GiveLoot(m.item, me, true)
	end
	Emit("disenchant", { sid = m.sid, sell = sell or nil })
	Announce(("%s will be %s."):format(ns.ItemLink(m.item), sell and "sold" or "disenchanted"))
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
	Announce(("the roll for %s was cancelled."):format(ns.ItemLink(m.item)))
end

-- The writer's correction of a roll's off-spec flag, before the first round closes.
function ns.ToggleOffSpec(id)
	local m = live.mirror
	if not ns.AmWriter() or not engine or not m or m.state ~= "open" or not m.entrants[id] then return end
	if m.greed or ns.ForEveryone(m.item) then return end -- nobody is off-spec for it
	local offSpec = not m.entrants[id].offSpec
	if engine:SetOffSpec(id, offSpec) then Emit("os", { sid = m.sid, id = id, os = offSpec or nil }) end
end

-- An officer's say on which roles an item is for (4.6), recorded in the ledger so every client agrees and
-- later drops use it. If the writer is running an open roll for the item, everyone's off-spec flag follows it.
function ns.SetItemRoles(item, suits)
	if not ns.IsOfficer(ns.PlayerName()) then return end
	local list = {}
	for _, role in ipairs(ns.ROLE_ORDER) do
		if suits[role] then list[#list + 1] = role end
	end
	local ok, err = ns.AppendEntry({ type = "roles", item = item, roles = list, time = GetServerTime(), by = ns.PlayerName() })
	if not ok then return ns.Print("The roles couldn't be recorded: " .. err .. ".") end
	local m = live.mirror
	if not (ns.AmWriter() and engine and m and m.state == "open" and m.item == item and not m.greed) then return end
	for id, entrant in pairs(m.entrants) do
		local offSpec = ns.IsOffSpec(id, item)
		if offSpec ~= nil and offSpec ~= (entrant.offSpec or false) and engine:SetOffSpec(id, offSpec) then
			Emit("os", { sid = m.sid, id = id, os = offSpec or nil })
		end
	end
end

-- Why you can't take part in the roll that's on, if you can't, for the window.
function ns.WhyCantRoll()
	local m = live.mirror
	if not IsActive(m) then return nil end
	local me = UnitGUID("player")
	if m.state == "reroll" then
		return not m.contenders[me] and "Only the tied players reroll" or nil
	end
	if m.greed then return nil end
	if ns.ledger and ns.ledger.state:HasWon(me, m.item) then return "You've won this item" end
	if not ns.CanUse(me, m.item) then return "Your class can't use this item" end
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
	if ns.ledger and ns.ledger.state:HasWon(id, item) then return false end
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

-- Passing: you won't roll in this round. It changes nothing in the ledger (not rolling never does, 4.1), but it takes
-- you out of everyone's odds, ends a reroll sooner, and stops auto-roll. A /roll afterwards still counts.
local function Passed(m, id, round)
	if not IsActive(m) or round ~= m.round or (m.rounds[m.round] and m.rounds[m.round][id]) then return end
	if m.state == "reroll" and not m.contenders[id] then return end
	m.passed[id] = round
	if id == UnitGUID("player") then StopAutoRoll(m) end
	RefreshOdds()
	ns.Fire("SESSION_CHANGED")
	if ns.AmWriter() then CloseIfAllRerolled(m) end
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

-- For the test commands: counts a roll from a made-up player, as if the writer had seen their /roll.
function ns.CountTestRoll(id, name, roll, pity, offSpec)
	local m = live.mirror
	if not ns.AmWriter() or not engine or not IsActive(m) then return false, "no roll is open" end
	if m.round > 1 then pity = nil end
	local ok, why = engine:AddRoll(id, roll, pity, offSpec)
	if not ok then return false, why end
	QueueRoll({ id = id, name = name, roll = roll, pity = pity, os = offSpec or nil })
	CloseIfAllRerolled(m)
	return true
end

-- Handover and late joiners ---------------------------------------------------------------------------------------

ns.Receive(LIVE, "writer", function(_, sender)
	if not ns.IsOfficer(sender) then return end
	if ns.AmWriter() then
		StopWriting()
		ns.Print(sender .. " has taken over as the writer.")
	end
	live.writer = sender
	SendLive("here", {}, sender)
	ns.Fire("SESSION_CHANGED")
end)

-- Whoever sends the writer anything has the addon: a reply to a new writer, a query, a pass.
ns.OnMessage(LIVE, function(sender)
	local member = ns.GroupMember(sender)
	if member then users[member.guid] = true end
end)

ns.Receive(LIVE, "query", function(_, sender)
	if not ns.AmWriter() then return end
	local m = live.mirror and ns.Copy(live.mirror)
	if m then m.odds, m.myOdds, m.ends, m.autoRollAt, m.rolledRound = nil, nil, nil, nil, nil end
	SendLive("state", {
		mirror = m, left = live.mirror and live.mirror.ends and live.mirror.ends - GetTime(), loot = ns.Copy(ns.loot),
	}, sender)
end)

ns.Receive(LIVE, "state", function(d, sender)
	if type(d) ~= "table" or not ns.IsOfficer(sender) then return end
	live.writer = sender
	local m = d.mirror
	if type(m) == "table" and type(m.sid) == "string" and type(m.entrants) == "table" and type(m.rounds) == "table" then
		m.partial = true
		m.passed = type(m.passed) == "table" and m.passed or {}
		m.ends = type(d.left) == "number" and GetTime() + d.left or nil
		live.mirror, live.observed = m, {}
	end
	ns.RestoreLoot(d.loot)
	Changed("state")
end)

ns.On("GROUP_ROSTER_UPDATE", function()
	if not IsInGroup() and not ns.IsTestMode() then
		StopWriting()
		live.writer, live.mirror, live.observed, queried = nil, nil, {}, false
	else
		if live.writer and not ns.GroupMember(live.writer) then
			ns.Print(live.writer .. ", the writer, has left the group. Another officer can take over with /pl writer.")
			live.writer = nil
		end
		if not queried then
			queried = true
			SendLive("query", {})
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
			if not m.entrants[me] then row.offSpec = not m.greed and ns.IsOffSpec(me, m.item) or nil end
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
		if not row.pity and ns.ledger then row.pity = ns.ledger.state:GetPity(row.id, m.item, m.greed, m.opened) end
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
		if not row.pity and ns.ledger then row.pity = ns.ledger.state:GetPity(row.id, m.item, m.greed, m.opened) end
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
