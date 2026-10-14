local addonName, ns = ...

-- The performance tests (design document 10, "Later features"): `/pl perf` times the heavy work on made-up data in the
-- real client, so anything slow shows up where it counts, and `/pl perf copy` shows the latest results to copy out. The
-- last few runs are kept in saved variables too (PitifulLootDB's `perf`), written on the next reload or logout.
-- Development only: never packaged (PitifulLoot.toc), so its text is English only, like the debugging commands.

local Clock = debugprofilestop or function() return GetTime() * 1000 end

local BUDGET = 250 -- milliseconds of timed runs per test, at most
local MIN_RUNS, MAX_RUNS = 3, 200
local FRAME = 1000 / 60 -- a frame at 60 fps: work slower than this on its own drops a frame
local GAP = 0.1 -- seconds between tests, so the game draws in between
local KEEP = 10 -- runs kept in saved variables

-- The made-up guild: 60 players, 40 of them raiding each week in each of two raids of 10 bosses with 12 items each, 3
-- of them dropping per boss, and about a third of the guild able to use each item; 12 weeks of results, the last of
-- them as changes not yet merged.
local GUILD, RAIDING, BOSSES, PER_BOSS, DROPS, WEEKS = 60, 40, 10, 12, 3, 12
local RAIDS = { "Halls of the Forever King", "Spire of the Unmade" }
local FIRST_ITEM = 240001
local WEEK = 7 * 24 * 60 * 60
local START = 1790000000 -- the first week, in server time
local KEY_ID = 1

-- Park-Miller, so the made-up data is the same every run.
local function NewRandom(seed)
	local x = seed
	return function(n)
		x = x * 16807 % 2147483647
		return x % n + 1
	end
end

local function Guid(i)
	return ("Player-4621-%08X"):format(0x0A000000 + i)
end

local function Copy(list)
	local out = {}
	for i, v in ipairs(list) do out[i] = v end
	return out
end

-- The made-up ledger: the table after every week, packed and signed, the table before the last week (packed), and the
-- last week's changes.
local function MakeData()
	local random = NewRandom(7)
	local officer = Guid(1)
	local ledger = ns.NewLedger()
	local eligible = {}
	local function Item(raid, boss, k)
		return FIRST_ITEM + ((raid - 1) * BOSSES + boss - 1) * PER_BOSS + k - 1
	end
	for raid, name in ipairs(RAIDS) do
		for b = 1, BOSSES do
			for k = 1, PER_BOSS do
				local item = Item(raid, b, k)
				ledger:Learn(item, name, "Boss " .. b)
				eligible[item] = {}
				for i = 1, GUILD do eligible[item][i] = random(3) == 1 end
			end
		end
	end
	local base, week, time
	for w = 1, WEEKS do
		if w == WEEKS then
			ledger:Commit(officer, time)
			base, week = ns.PackTable(ledger), {}
		end
		for raid, name in ipairs(RAIDS) do
			local guild = {}
			for i = 1, GUILD do table.insert(guild, random(#guild + 1), i) end
			for b = 1, BOSSES do
				for d = 1, DROPS do
					local item = Item(raid, b, random(PER_BOSS))
					local entrants = {}
					for r = 1, RAIDING do
						local guid = Guid(guild[r])
						if eligible[item][guild[r]] and random(5) > 1 and ledger:Cell(guid, item) ~= ns.CELL_WON then
							entrants[#entrants + 1] = guid
						end
					end
					if entrants[1] then
						local winner = table.remove(entrants, random(#entrants))
						time = START + (w - 1) * WEEK + (raid - 1) * 86400 + b * 600 + d
						local change = { op = "result", time = time, by = officer, n = 0, item = item, raid = name,
							boss = "Boss " .. b, losers = entrants, winners = { winner } }
						ledger:ApplyDiff(change)
						if week then week[#week + 1] = change end
					end
				end
			end
		end
	end
	ledger:Commit(officer, time)
	local key = ns.SHA256("Pitiful Loot performance tests")
	ledger:Sign(KEY_ID, key)
	local subRows, players = 0, 0
	for _, subs in pairs(ledger.data.rows) do
		players = players + 1
		for _ in pairs(subs) do subRows = subRows + 1 end
	end
	local packed = ns.PackTable(ledger)
	return {
		ledger = ledger, officer = officer, key = key, keys = { [KEY_ID] = key }, base = base, week = week,
		packed = packed, wrapped = ns.Wrap(packed), diffBytes = ns.EncodeDiffs(week), last = time,
		players = players, subRows = subRows, kilobyte = string.rep("Pitiful!", 128),
	}
end

-- A copy of the table before the last week, with the last week's changes pending on it (as an officer holds them
-- before a merge).
local function Pending(data)
	local copy = ns.Decode(ns.ReadTable, data.base)
	copy.base, copy.diffs = data.base, Copy(data.week)
	local ledger = ns.NewLedger(copy)
	ledger:Rebuild()
	return ledger
end

-- A pool of `size` players with a spread of pity, for the odds.
local function Pool(size)
	local pool = {}
	for i = 1, size do pool[i] = { id = Guid(i), pity = (i * 7 % 6) * 10, offSpec = i % 9 == 0 } end
	return pool
end

-- The odds keep every pool they've worked out, so each run asks for one more trial than the last to be a new one.
local extraTrials = 0
local function Odds(pool, copies)
	extraTrials = extraTrials + 1
	-- Odds.lua's trials for the pool's size, and for several copies
	ns.Odds(pool, copies, (copies > 1 and 2500 or #pool > 20 and 5000 or 10000) + extraTrials)
end

local SPREAD = "spread over frames in play" -- the odds: Odds.lua works them out a little each frame

-- Each test: `name`, `run` (timed), `each` (untimed, before each run, its result passed to run), `around` (runs the
-- timing inside it, for setting up and putting back), `skip` (why it can't run now, if it can't) and `note`.
local function Tests(data)
	local ledger = data.ledger
	local function Unsign()
		for _, subs in pairs(ledger.data.rows) do
			for _, sub in pairs(subs) do sub.sig = nil end
		end
	end
	local newChange = { op = "result", time = data.last + WEEK, by = data.officer, n = 0, item = FIRST_ITEM, raid = RAIDS[1],
		boss = "Boss 1", losers = { Guid(2), Guid(3), Guid(4), Guid(5), Guid(6) }, winners = { Guid(7) } }
	return {
		{ name = "SHA-256 of 1 KB", run = function() ns.SHA256(data.kilobyte) end },
		{
			name = ("Sign every sub-row (%d)"):format(data.subRows), each = Unsign,
			run = function() ledger:Sign(KEY_ID, data.key) end,
		},
		{
			name = ("Check every sub-row's signature (%d)"):format(data.subRows),
			run = function()
				for guid, subs in pairs(ledger.data.rows) do
					for raid, sub in pairs(subs) do ns.VerifyRow(data.keys, guid, raid, sub) end
				end
			end,
		},
		{
			name = ("Row checks for every player (%d)"):format(data.players),
			run = function()
				for guid, subs in pairs(ledger.data.rows) do ns.EncodeRowCheck(guid, subs) end
			end,
		},
		{ name = "Hash the table", run = function() ns.TableHash(ledger) end },
		{
			name = "Pack the table", run = function() ns.PackTable(ledger) end,
			note = ("%d bytes"):format(#data.packed),
		},
		{ name = "Read the packed table", run = function() ns.Decode(ns.ReadTable, data.packed) end },
		{
			name = "Wrap the packed table to send", run = function() ns.Wrap(data.packed) end,
			note = ("%d bytes"):format(#data.wrapped),
		},
		{ name = "Unwrap it", run = function() ns.Unwrap(data.wrapped) end },
		{
			name = ("Encode a week's changes (%d)"):format(#data.week), run = function() ns.EncodeDiffs(data.week) end,
			note = ("%d bytes"):format(#data.diffBytes),
		},
		{ name = "Read a week's changes", run = function() ns.Decode(ns.ReadDiffs, data.diffBytes) end },
		{
			name = "Take a new change (the hash waits until asked for)",
			each = function() return ns.NewLedger(ns.Decode(ns.ReadTable, data.packed)) end,
			run = function(copy) copy:AddDiff(newChange) end,
		},
		{
			name = ("Rebuild from the base and a week's changes (%d)"):format(#data.week),
			each = function() return Pending(data) end,
			run = function(copy) copy:Rebuild() end,
		},
		{
			name = ("Merge a week's changes (%d)"):format(#data.week),
			each = function() return Pending(data) end,
			run = function(copy) copy:Merge(data.officer, data.last + 60) end,
		},
		{ name = "Odds, 20 players, 1 copy", run = function() Odds(Pool(20), 1) end, note = SPREAD },
		{ name = "Odds, 40 players, 1 copy", run = function() Odds(Pool(40), 1) end, note = SPREAD },
		{ name = "Odds, 40 players, 2 copies", run = function() Odds(Pool(40), 2) end, note = SPREAD },
		-- Everyday work: your own role (the window keeps it for a frame; this is a fresh read each time), and whether
		-- each raider can need-roll on an item, as the Roll tab and the early end ask.
		{ name = "Read your talents", run = function() ns.ReadTalents() end },
		{
			name = "Read your gear's fit (every item worn)",
			run = function()
				local _, class = UnitClass("player")
				ns.GearFits("player", class, { TANK = true, HEALER = true, DAMAGER = true })
			end,
		},
		{
			name = "Can each of 40 raiders need-roll on an item",
			skip = not ns.IsTestMode() and "needs test mode, for a made-up raid"
				or not GetInventoryItemID("player", 5) and "needs a chest piece on" or nil,
			around = function(measure) ns.Test.WithRaid(40, measure) end,
			run = function()
				local item = GetInventoryItemID("player", 5)
				for _, member in ipairs(ns.GroupMembers()) do ns.MayRollOn(member.guid, item) end
			end,
		},
		{
			name = "Redraw the Raid tab, 40 players",
			skip = not ns.IsTestMode() and "needs test mode, for a made-up raid" or nil,
			around = function(measure)
				local window = ns.Window()
				local shown, view = window and window:IsShown(), ns.WindowView()
				ns.Test.WithRaid(40, function()
					ns.ShowWindow("raid")
					measure()
				end)
				if shown then ns.ShowWindow(view) else ns.Window():Hide() end
			end,
			run = function() ns.RefreshWindow() end,
		},
	}
end

-- Times a test: runs until it's had BUDGET milliseconds of runs (at least MIN_RUNS, at most MAX_RUNS). Returns its
-- result: runs, median, mean and slowest time in milliseconds, and roughly how much memory a run makes, in KB.
local function Measure(test)
	local times, made = {}, {}
	local function Runs()
		collectgarbage("collect")
		local spent, started = 0, Clock()
		while #times < MIN_RUNS or (#times < MAX_RUNS and spent < BUDGET and Clock() - started < 4 * BUDGET) do
			local arg = test.each and test.each()
			local before = collectgarbage("count")
			local t = Clock()
			test.run(arg)
			t = Clock() - t
			local grew = collectgarbage("count") - before
			times[#times + 1] = t
			if grew >= 0 then made[#made + 1] = grew end -- unless the collector ran meanwhile
			spent = spent + t
		end
	end
	if test.around then test.around(Runs) else Runs() end
	local sorted = Copy(times)
	table.sort(sorted)
	table.sort(made)
	local total = 0
	for _, t in ipairs(times) do total = total + t end
	return {
		name = test.name, runs = #times, median = sorted[math.ceil(#sorted / 2)], mean = total / #times,
		max = sorted[#sorted], kb = made[1] and made[math.ceil(#made / 2)] or nil, note = test.note,
	}
end

local function Ms(t)
	return ("%.2f"):format(t)
end

-- A result as a chat line: red if it would drop a frame on its own, orange if its slowest run would.
local function ChatLine(result)
	if result.skipped then return ("|cff808080%s: skipped, %s|r"):format(result.name, result.skipped) end
	local color = result.median > FRAME and "|cffff4040" or result.max > FRAME and "|cffff9933" or ""
	return ("%s%s: %s ms|r (slowest %s, %d runs)%s"):format(color, result.name, Ms(result.median), Ms(result.max),
		result.runs, result.note and ", " .. result.note or "")
end

-- A run's results as plain text, to copy out.
local function ResultText(run)
	local lines = {
		("Pitiful Loot performance, %s, client %s, addon %s"):format(run.when, run.client, run.version),
		("Made-up ledger: %d players with pity, %d sub-rows, %d weeks of results; a frame at 60 fps is %s ms; SHA-256 %s"):format(
			run.players, run.subRows, WEEKS, Ms(FRAME), run.crypto or "?"),
		"test | median ms | mean ms | slowest ms | runs | KB a run | note",
	}
	for _, r in ipairs(run.results) do
		if r.skipped then
			lines[#lines + 1] = ("%s | skipped: %s"):format(r.name, r.skipped)
		else
			lines[#lines + 1] = ("%s | %s | %s | %s | %d | %s | %s"):format(r.name, Ms(r.median), Ms(r.mean), Ms(r.max),
				r.runs, r.kb and ("%.1f"):format(r.kb) or "?", r.note or "")
		end
	end
	return table.concat(lines, "\n")
end

local running = false

local function Run()
	if running then return ns.Print("The performance tests are already running.") end
	if InCombatLockdown() then return ns.Print("Not in combat: the tests stall the game for a few seconds.") end
	running = true
	ns.Print("Running the performance tests: a few seconds, and the game will stutter meanwhile.")
	local started = Clock()
	local data = MakeData()
	local made = Clock() - started
	local version, build = GetBuildInfo()
	local run = {
		when = date("%Y-%m-%d %H:%M:%S"), client = ("%s (%s)"):format(version, build),
		version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?", players = data.players,
		subRows = data.subRows, made = made, results = {},
		crypto = ns.CRYPTO_FAST and "with three-argument bit calls" or "with two-argument bit calls",
	}
	local tests, i = Tests(data), 0
	local function Next()
		i = i + 1
		local test = tests[i]
		if not test then
			running = false
			local runs = ns.saved.perf or {}
			ns.saved.perf = runs
			runs[#runs + 1] = run
			while #runs > KEEP do table.remove(runs, 1) end
			ns.Print("Done. /pl perf copy shows the results to copy; they're saved on the next reload too.")
			return
		end
		local ok, result = true, nil
		if test.skip then
			result = { name = test.name, skipped = test.skip }
		else
			ok, result = pcall(Measure, test)
			if not ok then result = { name = test.name, skipped = "failed: " .. tostring(result) } end
		end
		run.results[#run.results + 1] = result
		ns.Print(ChatLine(result))
		C_Timer.After(GAP, Next)
	end
	C_Timer.After(GAP, Next)
end

local copyFrame

local function ShowCopy()
	local runs = ns.saved.perf
	local latest = runs and runs[#runs]
	if not latest then return ns.Print("No results yet: /pl perf runs the performance tests.") end
	if not copyFrame then
		copyFrame = CreateFrame("Frame", "PitifulLootPerfResults", UIParent, "BasicFrameTemplateWithInset")
		copyFrame:SetSize(640, 420)
		copyFrame:SetPoint("CENTER")
		copyFrame:SetFrameStrata("DIALOG")
		copyFrame:SetMovable(true)
		copyFrame:EnableMouse(true)
		copyFrame:RegisterForDrag("LeftButton")
		copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
		copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
		local title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		title:SetPoint("TOP", 0, -5)
		title:SetText("Pitiful Loot performance: Ctrl+C to copy")
		local scroll = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 12, -32)
		scroll:SetPoint("BOTTOMRIGHT", -32, 12)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetFontObject(ChatFontNormal)
		edit:SetWidth(590)
		edit:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
		scroll:SetScrollChild(edit)
		copyFrame.Edit = edit
		table.insert(UISpecialFrames, "PitifulLootPerfResults")
	end
	copyFrame.Edit:SetText(ResultText(latest))
	copyFrame:Show()
	copyFrame.Edit:SetFocus()
	copyFrame.Edit:HighlightText()
end

-- For the tests.
ns.PerfResultText = function() return ns.saved.perf and ResultText(ns.saved.perf[#ns.saved.perf]) end
ns.PerfRunning = function() return running end

ns.commands.perf = function(args)
	local sub = args[2] and args[2]:lower()
	if not sub then return Run() end
	if sub == "copy" then return ShowCopy() end
	ns.Print("/pl perf - run the performance tests; /pl perf copy - show the latest results to copy")
end
