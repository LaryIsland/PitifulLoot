local _, ns = ...

-- The audit log is the source of truth: the pity table is what you get by replaying every entry in order (6.1).
-- Each entry carries the hash of the one before it, so two copies with the same head hold the same history.

local GENESIS = "0000000000000000"
ns.GENESIS = GENESIS

local State = {}
State.__index = State

local function NewState()
	return setmetatable({ pity = {}, greed = {}, won = {}, left = {}, sources = {}, roles = {} }, State)
end

local function WeeksAway(left, now)
	return math.max(math.floor((now - left) / ns.LEAVER_DECAY_PERIOD), 0)
end

-- Pity on an item, less any leaver decay due by `now` (4.9). Greed-roll pity is a separate counter (4.8).
function State:GetPity(id, item, greed, now)
	local items = (greed and self.greed or self.pity)[id]
	local pity = items and items[item] or 0
	local left = self.left[id]
	if left and now then
		pity = math.max(pity - ns.LEAVER_DECAY * WeeksAway(left, now), 0)
	end
	return pity
end

function State:HasWon(id, item)
	return self.won[id] ~= nil and self.won[id][item] == true
end

-- Zero and false aren't stored, so equal tables come out of different histories.
local function Set(store, id, item, value)
	if value == 0 or value == false then value = nil end
	if value == nil and not store[id] then return end
	store[id] = store[id] or {}
	store[id][item] = value
	if next(store[id]) == nil then store[id] = nil end
end

local function IsCount(n)
	return type(n) == "number" and n % 1 == 0 and n >= 1
end

-- Where an item drops (the raid, and the boss if known), from the latest entry that says, for grouping pity by raid.
local function RecordSource(state, e)
	if type(e.instance) ~= "string" then return end
	state.sources[e.item] = { instance = e.instance, boss = type(e.boss) == "string" and e.boss or nil }
end

-- Each entry type checks everything before it changes anything, and returns an error if the entry is invalid.
local Apply = {}

function Apply.award(state, e)
	if type(e.item) ~= "number" or not IsCount(e.copies) or type(e.entrants) ~= "table" or type(e.rounds) ~= "table"
		or type(e.winners) ~= "table" then
		return "malformed award"
	end
	local first = e.rounds[1] or {}
	for id in pairs(first) do
		if not e.entrants[id] then return "a roll from " .. tostring(id) .. " with no entrant" end
	end
	for id, entrant in pairs(e.entrants) do
		local who = type(entrant.name) == "string" and entrant.name or id
		if not first[id] then return who .. " is an entrant but didn't roll" end
		-- Anyone may greed-roll, winners of the item included (4.8).
		if not e.greed and state:HasWon(id, e.item) then return who .. " has already won this item" end
		if entrant.pity ~= state:GetPity(id, e.item, e.greed, e.time) then
			return ("%s's pity (%d) doesn't match the table (%d)"):format(who, entrant.pity, state:GetPity(id, e.item, e.greed, e.time))
		end
	end

	-- The winners have to be the ones the recorded rolls produce.
	local session = ns.NewSession(e.item, e.copies, e.greed)
	for _, round in ipairs(e.rounds) do
		if session.done then return "a round after the roll was decided" end
		for id, roll in pairs(round) do
			local entrant = e.entrants[id]
			if not entrant then return "a reroll from " .. tostring(id) .. " who isn't an entrant" end
			local ok, why = session:AddRoll(id, roll, entrant.pity, entrant.offSpec)
			if not ok then return tostring(id) .. ": " .. why end
		end
		session:CloseRound()
	end
	if not session.done then return "the rolls don't decide the item" end
	local isWinner = {}
	for _, id in ipairs(session.winners) do isWinner[id] = true end
	local seen = {}
	for _, id in ipairs(e.winners) do
		if not isWinner[id] or seen[id] then return "the winners don't match the rolls" end
		seen[id] = true
	end
	if #e.winners ~= #session.winners then return "the winners don't match the rolls" end

	-- Everyone who rolled and didn't win gains pity, once, whatever happened in rerolls (4.1). Only a need win locks the
	-- winner out of the item; a greed winner can still need-roll it if it becomes an upgrade (4.8).
	local store = e.greed and state.greed or state.pity
	for id, entrant in pairs(e.entrants) do
		if isWinner[id] then
			if not e.greed then Set(state.won, id, e.item, true) end
		else
			Set(store, id, e.item, ns.AddPity(entrant.pity))
		end
	end
	RecordSource(state, e)
end

-- An officer's correction: sets pity on an item, and/or lifts a lockout given by mistake.
function Apply.adjust(state, e)
	if type(e.id) ~= "string" or type(e.item) ~= "number" then return "malformed adjustment" end
	if e.pity ~= nil and (type(e.pity) ~= "number" or e.pity % 1 ~= 0 or e.pity < 0 or e.pity > ns.PITY_MAX) then
		return "pity must be a whole number from 0 to " .. ns.PITY_MAX
	end
	if e.pity ~= nil then Set(e.greed and state.greed or state.pity, e.id, e.item, e.pity) end
	if e.unlock then Set(state.won, e.id, e.item, nil) end
	RecordSource(state, e)
end

-- An officer's say on which raid roles an item is main-spec for, in place of what its stats suggest (4.6). Every role,
-- or none, means anyone.
function Apply.roles(state, e)
	if type(e.item) ~= "number" or type(e.roles) ~= "table" then return "malformed roles" end
	local suits = {}
	for _, role in ipairs(e.roles) do
		if not ns.ROLE_NAMES[role] then return "unknown role " .. tostring(role) end
		suits[role] = true
	end
	state.roles[e.item] = suits
end

function Apply.leave(state, e)
	if type(e.id) ~= "string" then return "malformed leave" end
	if state.left[e.id] then return e.id .. " has already left" end
	state.left[e.id] = e.time
end

-- Decay stops when a leaver rejoins, and what they lost while away is taken off every item (4.9).
function Apply.rejoin(state, e)
	if type(e.id) ~= "string" then return "malformed rejoin" end
	local left = state.left[e.id]
	if not left then return e.id .. " hasn't left" end
	local loss = ns.LEAVER_DECAY * WeeksAway(left, e.time)
	for _, store in ipairs({ state.pity, state.greed }) do
		for item, pity in pairs(store[e.id] or {}) do
			Set(store, e.id, item, math.max(pity - loss, 0))
		end
	end
	state.left[e.id] = nil
end

local Ledger = {}
Ledger.__index = Ledger

-- The hash an entry should carry: of everything in it but the hash.
local function EntryHash(entry)
	local hash = entry.hash
	entry.hash = nil
	local text = ns.Serialize(entry)
	entry.hash = hash
	return ns.Hash(text)
end

-- Checks an entry follows on from the head and applies it. Nothing changes if it's rejected.
function Ledger:Accept(entry)
	if type(entry) ~= "table" then return false, "not an entry" end
	local rev = #self.entries + 1
	if entry.rev ~= rev then return false, "expected revision " .. rev end
	if entry.prev ~= self.head then return false, "doesn't follow on from revision " .. (rev - 1) end
	if entry.hash ~= EntryHash(entry) then return false, "the hash doesn't match the contents" end
	if type(entry.time) ~= "number" then return false, "no time" end
	local apply = Apply[entry.type]
	if not apply then return false, "unknown entry type " .. tostring(entry.type) end
	local err = apply(self.state, entry)
	if err then return false, err end
	self.entries[rev] = entry
	self.head = entry.hash
	return true
end

-- Stamps a new entry with its revision, the head it follows and its hash, then accepts it.
function Ledger:Append(entry)
	entry.rev = #self.entries + 1
	entry.prev = self.head
	entry.hash = EntryHash(entry)
	return self:Accept(entry)
end

function Ledger:Revision()
	return #self.entries, self.head
end

-- Replays saved entries into a new ledger. Stops at the first bad entry and returns its position and the error.
function ns.LoadLedger(entries)
	local ledger = setmetatable({ entries = {}, state = NewState(), head = GENESIS }, Ledger)
	for i, entry in ipairs(entries or {}) do
		local ok, err = ledger:Accept(entry)
		if not ok then return ledger, i, err end
	end
	return ledger
end
