local _, ns = ...

local TRIALS = 10000
local TRIALS_PER_FRAME = 1000

-- Park-Miller generator. The odds are seeded from the pool, so every client shows the same numbers for it.
local function NewRandom(seed)
	local x = seed % 2147483646 + 1
	return function(n)
		x = x * 16807 % 2147483647
		return x % n + 1
	end
end

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
	local random = NewRandom(tonumber(ns.Hash(table.concat(key, ",") .. ";" .. copies):sub(1, 8), 16))

	local wins = {}
	for trial = 1, trials do
		if yields and trial % TRIALS_PER_FRAME == 0 then coroutine.yield() end
		local contenders, slots = players, copies
		while true do
			for _, c in ipairs(contenders) do c.roll = random(ns.ROLL_MAX) end
			local winners, tied, left = ns.RankRound(contenders, slots)
			for _, id in ipairs(winners) do
				local bonus = players[id].bonus
				wins[bonus] = (wins[bonus] or 0) + 1
			end
			if not tied then break end
			contenders, slots = {}, left
			for i, id in ipairs(tied) do contenders[i] = players[id] end
		end
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
function ns.Odds(pool, copies, trials)
	return Calculate(pool, copies or 1, trials or TRIALS, false)
end

local job

-- The same, spread over frames so the client doesn't stall, then calls callback(chances). Starting another
-- calculation, when the pool changes, drops the one in progress.
function ns.OddsLater(pool, copies, callback)
	local mine = coroutine.create(Calculate)
	job = mine
	local function Step()
		if job ~= mine then return end
		local ok, chances = coroutine.resume(mine, pool, copies or 1, TRIALS, true)
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
