local _, ns = ...

-- Sorts players on `key` and gives copies out from the top. A group tied across the last copy left gets none of
-- them; it's returned with the number of copies left so they can be rolled off.
local function Assign(players, slots, key, winners)
	table.sort(players, function(a, b)
		if a[key] ~= b[key] then return a[key] > b[key] end
		return a.id < b.id
	end)
	local i = 1
	while i <= #players and slots > 0 do
		local j = i
		while j < #players and players[j + 1][key] == players[i][key] do j = j + 1 end
		if j - i + 1 <= slots then
			for k = i, j do winners[#winners + 1] = players[k].id end
			slots = slots - (j - i + 1)
		else
			local tied = {}
			for k = i, j do tied[#tied + 1] = players[k] end
			return slots, tied
		end
		i = j + 1
	end
	return slots
end

local function SameBonus(players)
	for i = 2, #players do
		if players[i].bonus ~= players[1].bonus then return false end
	end
	return true
end

-- Ranks one round of rolls for `slots` copies (4.3, 4.3a).
-- contenders: array of { id = guid, bonus = pity + modifier, roll = 1-100 }.
-- Returns the ids that won a copy, then, if some copies are still undecided, the ids who must reroll for them and
-- how many copies that is. Players tied only because the clamp at 100 caught them all, with the same bonus, are
-- separated by their raw rolls: that gives exactly the odds of a reroll without making them /roll again.
function ns.RankRound(contenders, slots)
	local players = {}
	for i, c in ipairs(contenders) do
		players[i] = { id = c.id, bonus = c.bonus, roll = c.roll, value = ns.EffectiveRoll(c.roll, c.bonus) }
	end
	local winners = {}
	local left, tied = Assign(players, slots, "value", winners)
	if tied and SameBonus(tied) then
		left, tied = Assign(tied, left, "roll", winners)
	end
	if not tied then return winners end
	local ids = {}
	for i, p in ipairs(tied) do ids[i] = p.id end
	return winners, ids, left
end

-- One item's roll (5.1). Rounds are maps of id to roll; the first is open to anyone, later ones only to the players
-- who tied. Entrants are recorded with the pity they had when their first roll was seen.
local Session = {}
Session.__index = Session

function ns.NewSession(item, copies, greed)
	copies = copies or 1
	return setmetatable({
		item = item,
		copies = copies,
		greed = greed or nil,
		entrants = {},
		rounds = { {} },
		slots = copies,
		winners = {},
	}, Session)
end

-- Returns true if the roll counts, or false and why it doesn't.
function Session:AddRoll(id, roll, pity, offSpec)
	if self.done then return false, "the roll is over" end
	if type(roll) ~= "number" or roll % 1 ~= 0 or roll < ns.ROLL_MIN or roll > ns.ROLL_MAX then
		return false, "not a roll from 1 to 100"
	end
	local round = self.rounds[#self.rounds]
	if round[id] then return false, "already rolled" end
	if self.contenders and not self.contenders[id] then return false, "not in the reroll" end
	if #self.rounds == 1 then
		if type(pity) ~= "number" then return false, "no pity given" end
		self.entrants[id] = { pity = pity, offSpec = offSpec or nil }
	end
	round[id] = roll
	return true
end

-- The writer's correction of an entrant's off-spec flag (4.6), only before the first round closes.
function Session:SetOffSpec(id, offSpec)
	local entrant = self.entrants[id]
	if not entrant or #self.rounds > 1 or self.done then return false end
	entrant.offSpec = offSpec or nil
	return true
end

-- Ends the current round. Returns "done", or "reroll" and the ids who must reroll. Tied players who don't reroll
-- are left out of the next round.
function Session:CloseRound()
	if self.done then return "done" end
	local contenders = {}
	for id, roll in pairs(self.rounds[#self.rounds]) do
		local entrant = self.entrants[id]
		contenders[#contenders + 1] = { id = id, roll = roll, bonus = ns.Bonus(entrant.pity, entrant.offSpec) }
	end
	local winners, tied, left = ns.RankRound(contenders, self.slots)
	for _, id in ipairs(winners) do self.winners[#self.winners + 1] = id end
	if not tied then
		self.done = true
		return "done"
	end
	self.slots = left
	self.contenders = {}
	for _, id in ipairs(tied) do self.contenders[id] = true end
	self.rounds[#self.rounds + 1] = {}
	return "reroll", tied
end

local function Copy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = Copy(v) end
	return c
end

-- The finished roll as an audit log entry (6.3).
function Session:Record()
	return {
		type = "award",
		item = self.item,
		copies = self.copies,
		greed = self.greed,
		entrants = Copy(self.entrants),
		rounds = Copy(self.rounds),
		winners = Copy(self.winners),
	}
end

ns.Copy = Copy
