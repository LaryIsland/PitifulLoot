local _, ns = ...

-- The writer's queue (5.2): Loot tab entries waiting for the roll under way, in the order they're to roll. Clicking an
-- item while there's a roll under way queues it, or takes it back out, and a boss's dice button queues its loot. Each
-- starts a moment after the roll before it is awarded, disenchanted, auctioned or cancelled, just as if the writer
-- had started it, so raid chat hears nothing new; that moment counts as the roll still being under way. Whatever would
-- hold the writer up holds the queue up too: a tie, a roll waiting for Award, one no one rolled on. Clear Queue empties
-- it. It runs in the background: a roll it starts, Roll all's first included, opens the Roll tab only if the writer
-- can roll on it, as for anyone, and a roll with more queued behind it doesn't take the writer back to the Loot tab
-- once it's dealt with (the last one does). It's kept on the writer's client and not saved.
--
-- Raiders see it too, without the writer's clicking items in and out of it sending anything: the writer shares it only
-- as a roll is dealt with or cancelled, and only if it's changed since; or when it's emptied with no roll coming. Each
-- client takes an item off as its roll starts, the writer's copy of what it shared included, so the queue moving on
-- sends nothing either. A late joiner gets it with the rest of the roll's state.

local GAP = 3 -- seconds between one roll being dealt with and the next starting
local LIVE = ns.PREFIX_LIVE

local queue = {}
local nextTimer
local starting = false -- while the queue starts a roll
local shared = {} -- the writer's: the queue as raiders have it, from what it last shared
local seen, seenFrom = {}, nil -- a raider's: the writer's queue as last shared, and which writer shared it

local function Rollable(entry)
	return entry.status == "waiting" or entry.status == "none"
end

-- Nothing is happening that the writer has still to deal with.
local function Idle()
	local m = ns.live.mirror
	return not m or m.state == "awarded" or m.state == "disenchanted" or m.state == "kept" or m.state == "cancelled"
end

local function CancelNext()
	if nextTimer then nextTimer:Cancel() end
	nextTimer = nil
end

-- A list without what there's no longer a roll to start for: started, dealt with, or gone from the loot.
local function Still(list)
	local present = {}
	for _, group in ipairs(ns.loot.groups) do
		for _, entry in ipairs(group.items) do present[entry] = true end
	end
	local kept = {}
	for _, entry in ipairs(list) do
		if present[entry] and Rollable(entry) then kept[#kept + 1] = entry end
	end
	return kept
end

-- Keeps every copy of the queue to what can still be rolled for. The writer's own goes once you're not the writer, and
-- a raider's copy once someone else is.
local function Prune()
	if not ns.AmWriter() then
		queue, shared = {}, {}
		local writer = ns.live.writer
		seen = seenFrom and writer and ns.SameName(seenFrom, writer) and Still(seen) or {}
	else
		queue, shared, seen = Still(queue), Still(shared), {}
	end
	if not queue[1] then CancelNext() end
end
ns.Listen("LOOT_CHANGED", Prune)
ns.Listen("SESSION_CHANGED", Prune)

-- Starts the queue's next roll, if nothing's in the way.
local function StartNext()
	nextTimer = nil
	Prune()
	if queue[1] and Idle() then
		starting = true
		ns.RollEntry(queue[1])
		starting = false
	end
	ns.Fire("QUEUE_CHANGED")
end

-- Whether the queue is starting a roll right now, so it opens in the background.
function ns.QueueStarting()
	return starting
end

local function PositionIn(list, entry)
	for i, queued in ipairs(list) do
		if queued == entry then return i end
	end
end

-- An entry's place in the writer's queue, 1 being next; nil if it isn't in it.
function ns.QueuePosition(entry)
	return PositionIn(queue, entry)
end

-- The number behind an entry's row on the Loot tab, while there's a queue, for the writer and raiders alike: 1 for
-- the roll under way, if there is one, then the queue's in order after it.
function ns.QueueNumber(entry)
	local list = ns.AmWriter() and queue or seen
	if not list[1] then return nil end
	local m = ns.live.mirror
	local current = not Idle() and m.sid ~= nil
	if current and entry.sid == m.sid then return 1 end
	local at = PositionIn(list, entry)
	return at and (current and at + 1 or at)
end

-- How raiders find an entry: its loot by the corpse it came from (or failing that, what's in it, as loot opened twice
-- is recognised), and its place in that loot.
local function Ref(entry)
	for _, group in ipairs(ns.loot.groups) do
		for i, each in ipairs(group.items) do
			if each == entry then return { g = group.source or group.contents, i = i } end
		end
	end
end

local function Resolve(ref)
	if type(ref) ~= "table" or type(ref.g) ~= "string" or type(ref.i) ~= "number" then return nil end
	local groups = ns.loot.groups
	for g = #groups, 1, -1 do
		if (groups[g].source or groups[g].contents) == ref.g then return groups[g].items[ref.i] end
	end
end

-- The writer's queue as raiders are sent it.
function ns.QueueToShare()
	local refs = {}
	for _, entry in ipairs(queue) do refs[#refs + 1] = Ref(entry) end
	return refs
end

-- Shares the writer's queue with the group, if it's changed from what raiders have.
local function Share()
	if not ns.AmWriter() then return end
	local same = #queue == #shared
	for i, entry in ipairs(queue) do same = same and shared[i] == entry end
	if same then return end
	shared = { unpack(queue) }
	if IsInGroup() then ns.Send(LIVE, "queue", { list = ns.QueueToShare() }, IsInRaid() and "RAID" or "PARTY") end
end

-- A raider taking the writer's queue, from `writer`.
function ns.TakeSharedQueue(list, writer)
	if ns.AmWriter() then return end
	seen, seenFrom = {}, writer
	for _, ref in ipairs(type(list) == "table" and list or {}) do seen[#seen + 1] = Resolve(ref) end
	seen = Still(seen)
	ns.Fire("QUEUE_CHANGED")
end

ns.Receive(LIVE, "queue", function(d, sender)
	if type(d) ~= "table" or not ns.IsOfficer(sender) then return end
	if not (ns.live.writer and ns.SameName(sender, ns.live.writer)) then return end
	ns.TakeSharedQueue(d.list, sender)
end)

-- Whether clicking an item queues it rather than starting its roll: a roll is under way, or the queue's next is about
-- to start.
function ns.QueueBusy()
	return ns.AmWriter() and (not Idle() or nextTimer ~= nil)
end

-- Whether the queue's next roll is about to start, in the moment after the one before.
function ns.QueueGap()
	return ns.AmWriter() and nextTimer ~= nil
end

function ns.ToggleQueued(entry)
	local at = ns.QueuePosition(entry)
	if at then
		table.remove(queue, at)
		if not queue[1] then CancelNext() end
	elseif ns.AmWriter() and Rollable(entry) then
		queue[#queue + 1] = entry
	end
	-- With no roll under way or coming, there's no roll to be dealt with to share it.
	if not ns.QueueBusy() then Share() end
	ns.Fire("QUEUE_CHANGED")
end

-- Whether there's anything in the queue, when the window offers to clear it.
function ns.HasQueue()
	return ns.AmWriter() and queue[1] ~= nil
end

function ns.ClearQueue()
	queue = {}
	CancelNext()
	if not ns.QueueBusy() then Share() end
	ns.Fire("QUEUE_CHANGED")
end

-- Whether a boss's loot has anything still to roll for that isn't queued yet.
function ns.CanRollAll(group)
	if not ns.AmWriter() then return false end
	for _, entry in ipairs(group.items) do
		if entry.status == "waiting" and not ns.QueuePosition(entry) then return true end
	end
	return false
end

-- Queues every item in a boss's loot still to roll for, in loot order, need rolls before greed rolls; the first
-- starts straight away if nothing's going on.
function ns.RollAll(group)
	if not ns.AmWriter() then return end
	local need, greed = {}, {}
	for _, entry in ipairs(group.items) do
		if entry.status == "waiting" and not ns.QueuePosition(entry) then
			local list = (ns.ForEveryone(entry.item) or ns.NeedViable(entry.item)) and need or greed
			list[#list + 1] = entry
		end
	end
	for _, entry in ipairs(need) do queue[#queue + 1] = entry end
	for _, entry in ipairs(greed) do queue[#queue + 1] = entry end
	if ns.QueueBusy() then return ns.Fire("QUEUE_CHANGED") end
	StartNext()
end

-- A roll dealt with or cancelled shares the queue, if it's changed, and moves it on a moment later.
ns.Listen("ROLL_EVENT", function(kind)
	if kind ~= "awarded" and kind ~= "disenchant" and kind ~= "cancel" then return end
	Prune()
	Share()
	if nextTimer or not queue[1] then return end
	nextTimer = C_Timer.NewTimer(GAP, StartNext)
	ns.Fire("QUEUE_CHANGED")
end)
