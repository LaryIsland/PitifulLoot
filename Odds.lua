local _, ns = ...

local TRIALS = 10000
local LARGE_POOL, LARGE_POOL_TRIALS = 20, 5000 -- big pools (a 40-player raid) settle on fewer trials; still within ~1%
local TRIALS_PER_FRAME = 1000 -- at most, per frame
local FRAME_BUDGET = 2 -- milliseconds a frame may spend on odds; it yields sooner if a frame's share takes longer
local CHECK_EVERY = 25 -- trials between looks at the clock
local CACHE_SIZE = 64

local Clock = debugprofilestop or function() return GetTime() * 1000 end

-- Park-Miller generator. The odds are seeded from the pool, so every client shows the same numbers for it.
local function NewRandom(seed)
	local x = seed % 2147483646 + 1
	return function(n)
		x = x * 16807 % 2147483647
		return x % n + 1
	end
end

-- One trial for a single copy, ranked exactly as ns.RankRound ranks a round (the highest effective roll wins; a tie
-- of players with the same bonus goes to the higher raw roll; any other tie rerolls), but without building any
-- tables, as this runs ten thousand times. Returns the winner's index into players.
local list, ties, raw = {}, {}, {}
local function SingleWinner(players, random)
	local count = #players
	for k = 1, count do list[k] = k end
	while true do
		local best, tied = -1000, 0
		for k = 1, count do
			local p = players[list[k]]
			local roll = random(100)
			p.roll = roll
			local value = roll + p.bonus
			if value > 100 then value = 100 end
			if value > best then
				best, tied = value, 1
				ties[1] = list[k]
			elseif value == best then
				tied = tied + 1
				ties[tied] = list[k]
			end
		end
		if tied == 1 then return ties[1] end
		local sameBonus = true
		for k = 2, tied do
			if players[ties[k]].bonus ~= players[ties[1]].bonus then
				sameBonus = false
				break
			end
		end
		if sameBonus then
			local bestRoll, rawTied = -1, 0
			for k = 1, tied do
				local roll = players[ties[k]].roll
				if roll > bestRoll then
					bestRoll, rawTied = roll, 1
					raw[1] = ties[k]
				elseif roll == bestRoll then
					rawTied = rawTied + 1
					raw[rawTied] = ties[k]
				end
			end
			if rawTied == 1 then return raw[1] end
			for k = 1, rawTied do list[k] = raw[k] end
			count = rawTied
		else
			for k = 1, tied do list[k] = ties[k] end
			count = tied
		end
	end
end

-- One trial for several copies, through the real ranking. Adds each winner's bonus to wins.
local function SeveralWinners(players, copies, random, wins)
	local contenders, slots = players, copies
	while true do
		for _, c in ipairs(contenders) do c.roll = random(ns.ROLL_MAX) end
		local winners, tied, left = ns.RankRound(contenders, slots)
		for _, id in ipairs(winners) do
			local bonus = players[id].bonus
			wins[bonus] = (wins[bonus] or 0) + 1
		end
		if not tied then return end
		contenders, slots = {}, left
		for i, id in ipairs(tied) do contenders[i] = players[id] end
	end
end

-- Pools already worked out, by their make-up, so the same pool is never simulated twice.
local cache, cached = {}, 0

local function Calculate(pool, copies, trials, yields)
	local chances = {}
	local counts, bonuses = {}, {}
	for _, p in ipairs(pool) do
		local bonus = ns.Bonus(p.pity, p.offSpec)
		if not counts[bonus] then bonuses[#bonuses + 1] = bonus end
		counts[bonus] = (counts[bonus] or 0) + 1
	end

	-- Everyone the same, or enough copies for everyone: no need to simulate.
	if #bonuses <= 1 or copies >= #pool then
		for _, p in ipairs(pool) do chances[p.id] = math.min(copies / #pool, 1) end
		return chances
	end

	table.sort(bonuses)
	local key, players = {}, {}
	for i, bonus in ipairs(bonuses) do
		key[i] = bonus .. "x" .. counts[bonus]
		for _ = 1, counts[bonus] do players[#players + 1] = { id = #players + 1, bonus = bonus } end
	end
	key = table.concat(key, ",") .. ";" .. copies .. ";" .. trials

	local wins = cache[key]
	if not wins then
		wins = {}
		local random = NewRandom(tonumber(ns.Hash(key):sub(1, 8), 16))
		local started, sinceYield = Clock(), 0
		for trial = 1, trials do
			if copies == 1 then
				local bonus = players[SingleWinner(players, random)].bonus
				wins[bonus] = (wins[bonus] or 0) + 1
			else
				SeveralWinners(players, copies, random, wins)
			end
			sinceYield = sinceYield + 1
			if yields and (sinceYield >= TRIALS_PER_FRAME
				or (trial % CHECK_EVERY == 0 and Clock() - started > FRAME_BUDGET)) then
				coroutine.yield()
				started, sinceYield = Clock(), 0
			end
		end
		if cached >= CACHE_SIZE then cache, cached = {}, 0 end
		cache[key], cached = wins, cached + 1
	end

	for _, p in ipairs(pool) do
		local bonus = ns.Bonus(p.pity, p.offSpec)
		chances[p.id] = (wins[bonus] or 0) / (trials * counts[bonus])
	end
	return chances
end

-- Each player's chance of winning one of `copies` copies (5.2), from who is in the pool and their pity alone, never
-- from rolls already made. pool: array of { id = guid, pity = n, offSpec = bool }. Approximate: it plays the roll out
-- `trials` times with the same ranking and rerolls as the real one. Players with the same bonus share a figure.
local function TrialsFor(pool)
	return #pool > LARGE_POOL and LARGE_POOL_TRIALS or TRIALS
end

function ns.Odds(pool, copies, trials)
	return Calculate(pool, copies or 1, trials or TrialsFor(pool), false)
end

local job

-- The same, spread over frames so the client doesn't stall, then calls callback(chances). Starting another
-- calculation, when the pool changes, drops the one in progress.
function ns.OddsLater(pool, copies, callback)
	local mine = coroutine.create(Calculate)
	job = mine
	local function Step()
		if job ~= mine then return end
		local ok, chances = coroutine.resume(mine, pool, copies or 1, TrialsFor(pool), true)
		if not ok then
			job = nil
			error(chances)
		elseif coroutine.status(mine) == "dead" then
			job = nil
			callback(chances)
		else
			C_Timer.After(0, Step)
		end
	end
	Step()
end

-- The exact chance a player with `bonus` beats one with no pity, one on one, ties rerolled (7.1).
local headToHead = {}
function ns.HeadToHead(bonus)
	if not headToHead[bonus] then
		local wins, tied = 0, 0
		for a = 1, ns.ROLL_MAX do
			local mine = ns.EffectiveRoll(a, bonus)
			for b = 1, ns.ROLL_MAX do
				if mine > b then wins = wins + 1 elseif mine == b then tied = tied + 1 end
			end
		end
		local total = ns.ROLL_MAX * ns.ROLL_MAX
		headToHead[bonus] = wins / (total - tied)
	end
	return headToHead[bonus]
end
