local _, ns = ...

-- Keeping everyone's copy of the ledger up to date (6.3). Only officers' copies count: entries are only taken from
-- officers, and every one is replayed and checked before it's kept. Everyone says hello to the guild when they log
-- in; anyone behind an officer pulls the entries they're missing from that officer. A copy that doesn't follow on
-- from an officer's is never overwritten silently; it's reported, and /pl resync replaces it.
--
--   hello   {rev, head}          guild, on login; an officer ahead of the sender answers with theirs
--   get     {from, head}         whisper to an officer: entries from `from`, if `head` is their hash at from - 1
--   entries {list, last}         whisper reply, in batches
--   diverged {rev}               whisper reply when `head` doesn't match
--   entry   {entry}              guild, when an officer records something new

local SYNC = ns.PREFIX_SYNC
local BATCH = 10
local STALE = 60 -- seconds without progress before a pull from one officer can be given up for another
local HELLO_DELAY = 5
local HELLO_INTERVAL = 30

local pull
local reported = {}
local lastHello = -HELLO_INTERVAL

local function Revision()
	if not ns.ledger then return 0, ns.GENESIS end
	return ns.ledger:Revision()
end

-- Whether this copy might be behind, so the writer shouldn't record anything yet.
function ns.SyncBusy()
	return pull ~= nil and GetTime() - pull.last < STALE
end

local function Diverged(officer, rev)
	local key = officer .. ":" .. rev
	if reported[key] then return end
	reported[key] = true
	ns.Warn(("Your ledger differs from %s's at revision %d. If theirs is right, /pl resync %s replaces yours.")
		:format(officer, rev, ns.ShortName(officer)))
end

local function Pull(officer, replace)
	if ns.SyncBusy() and not replace then return end
	local rev, head = Revision()
	pull = { from = officer, last = GetTime(), replace = replace }
	if replace then
		pull.ledger = ns.LoadLedger()
		rev, head = 0, ns.GENESIS
	end
	ns.Send(SYNC, "get", { from = rev + 1, head = head }, "WHISPER", officer)
	ns.Fire("SYNC_CHANGED")
end

local function SayHello()
	if not ns.ledger then return end
	local rev, head = Revision()
	lastHello = GetTime()
	ns.Send(SYNC, "hello", { rev = rev, head = head }, "GUILD")
end

ns.Listen("LEDGER_READY", function()
	pull, reported = nil, {}
	if ns.ledger then C_Timer.After(HELLO_DELAY, SayHello) end
end)

-- Replaces this copy with an officer's.
function ns.Resync(officer)
	local member = ns.GuildMember(officer)
	if not member or not ns.IsOfficer(member.name) then
		return ns.Print((officer or "?") .. " isn't an officer in your guild.")
	end
	ns.Print("Fetching the ledger from " .. member.name .. ".")
	Pull(member.name, true)
end

-- Records an entry on this officer's copy and tells the guild.
function ns.AppendEntry(entry)
	if not ns.ledger then return false, "you're not in a guild" end
	if not ns.IsOfficer(ns.PlayerName()) then return false, "only officers can record entries" end
	if ns.SyncBusy() then return false, "your ledger is still syncing" end
	local ok, err = ns.ledger:Append(entry)
	ns.Capture("append", entry, ok, err)
	if not ok then return false, err end
	ns.Send(SYNC, "entry", { entry = entry }, "GUILD")
	ns.Fire("LEDGER_CHANGED")
	return true
end

ns.Receive(SYNC, "hello", function(d, sender)
	if not ns.ledger or type(d) ~= "table" or type(d.rev) ~= "number" or type(d.head) ~= "string" then return end
	local rev, head = Revision()
	if ns.IsOfficer(sender) then
		if d.rev > rev then
			Pull(sender)
		elseif d.rev > 0 and ns.ledger.entries[d.rev].hash ~= d.head then
			Diverged(sender, d.rev)
		end
	end
	-- An officer ahead of the sender answers with a hello of their own, to the whole guild, so a few people logging
	-- in together cost one message.
	if rev > d.rev and ns.IsOfficer(ns.PlayerName()) and GetTime() - lastHello > HELLO_INTERVAL then
		lastHello = GetTime()
		ns.Send(SYNC, "hello", { rev = rev, head = head }, "GUILD")
	end
end)

ns.Receive(SYNC, "get", function(d, sender)
	if not ns.ledger or not ns.IsOfficer(ns.PlayerName()) then return end
	if type(d) ~= "table" or type(d.from) ~= "number" or d.from < 1 or d.from % 1 ~= 0 then return end
	local entries = ns.ledger.entries
	local before = entries[d.from - 1]
	if (before and before.hash or ns.GENESIS) ~= d.head or d.from - 1 > #entries then
		return ns.Send(SYNC, "diverged", { rev = d.from - 1 }, "WHISPER", sender)
	end
	if d.from > #entries then
		return ns.Send(SYNC, "entries", { list = {}, last = true }, "WHISPER", sender)
	end
	for first = d.from, #entries, BATCH do
		local list = {}
		for i = first, math.min(first + BATCH - 1, #entries) do list[#list + 1] = entries[i] end
		ns.Send(SYNC, "entries", { list = list, last = first + BATCH > #entries }, "WHISPER", sender)
	end
end)

ns.Receive(SYNC, "entries", function(d, sender)
	if not pull or not ns.SameName(pull.from, sender) or type(d) ~= "table" or type(d.list) ~= "table" then return end
	pull.last = GetTime()
	local ledger = pull.replace and pull.ledger or ns.ledger
	for _, entry in ipairs(d.list) do
		local mine = type(entry) == "table" and ledger.entries[entry.rev]
		if mine then
			if mine.hash ~= entry.hash then
				pull = nil
				return Diverged(sender, entry.rev)
			end
		else
			local ok, err = ledger:Accept(entry)
			if not ok then
				pull = nil
				ns.Warn(("Revision %s from %s was refused: %s."):format(tostring(type(entry) == "table" and entry.rev), sender, err))
				ns.Fire("SYNC_CHANGED")
				return
			end
			if not pull.replace then ns.CheckEntry(entry) end
		end
	end
	if d.last then
		if pull.replace then
			ns.ReplaceLedger(pull.ledger)
			ns.Print(("Your ledger now matches %s's (revision %d)."):format(sender, #pull.ledger.entries))
		end
		pull = nil
		ns.Fire("SYNC_CHANGED")
	end
	ns.Fire("LEDGER_CHANGED")
end)

ns.Receive(SYNC, "diverged", function(d, sender)
	if not pull or not ns.SameName(pull.from, sender) or type(d) ~= "table" or type(d.rev) ~= "number" then return end
	pull = nil
	Diverged(sender, d.rev)
	ns.Fire("SYNC_CHANGED")
end)

ns.Receive(SYNC, "entry", function(d, sender)
	if not ns.ledger or not ns.IsOfficer(sender) or type(d) ~= "table" or type(d.entry) ~= "table" then return end
	local entry = d.entry
	local rev = Revision()
	if type(entry.rev) ~= "number" then return end
	if entry.rev == rev + 1 and not ns.SyncBusy() then
		local ok, err = ns.ledger:Accept(entry)
		if not ok then
			return ns.Warn(("Revision %d from %s was refused: %s."):format(entry.rev, sender, err))
		end
		ns.CheckEntry(entry)
		ns.Fire("LEDGER_CHANGED")
	elseif entry.rev > rev + 1 then
		Pull(sender)
	elseif ns.ledger.entries[entry.rev] and ns.ledger.entries[entry.rev].hash ~= entry.hash then
		Diverged(sender, entry.rev)
	end
end)
