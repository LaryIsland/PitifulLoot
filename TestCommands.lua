local _, ns = ...

-- Test mode, which the test menu (TestMenu.lua) runs on and which stays after release as part of that tutorial, and
-- the /pl test commands for trying the addon out in game, alone or with friends. The debugging commands (probe,
-- capture, warn, trust, trade, owed) are temporary, and their text isn't translated (design document 5.5); anything
-- the test menu leads to is, in Locales as the TEST_MSG_ lines.
--
-- Test mode is never on in a raid instance or a raid group: it can't be turned on there, and turns itself off on the
-- way in. It keeps to this client unless someone in your group is trusted (ns.TestIsPrivate).
-- Everything runs in test mode, which keeps its own ledger, counts you as an officer, lets you be the writer without
-- a group, and sends and accepts no ledger sync, so nothing done here reaches the guild's real ledger. Live roll
-- messages still go to your group, so friends in test mode who trust you (/pl test trust <you>) see your rolls.
-- On your own, the writer's raid chat and raid warnings are previewed as the raid would see them (Session.lua).

local L = ns.L
local NAMES = {
	"Aldric", "Brenna", "Corwin", "Dalia", "Edric", "Fenna", "Garrick", "Hilde", "Ivor", "Jessa",
	"Kael", "Liora", "Marek", "Nessa", "Orrin", "Petra", "Quill", "Rowan", "Sela", "Tamsin",
}
local OFF_SPEC_CHANCE = 0.25
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
-- Made-up raids and bosses for test pity, so the My pity groups can be seen.
local TEST_RAIDS = {
	{ "Test Raid A", { "First Boss", "Second Boss", "Third Boss" } },
	{ "Test Raid B", { "Fourth Boss", "Fifth Boss" } },
}

local HELP = {
	"/pl test - the test menu, which walks through a raid night on your own (TestMenu.lua)",
	"/pl test help - these commands",
	"/pl test on | off - test mode: a separate ledger, you count as an officer, no ledger sync",
	"/pl test reset - empty the test ledger and the Loot tab, and cancel your roll",
	"/pl test pity [count] [name] - random pity on random items you're wearing, from made-up raids (for someone else with a name)",
	"/pl test roll [item] [copies] - become the writer and start a roll (a random item you're wearing if none is given)",
	"/pl test rollers [count] - the made-up raiders roll in the open roll, or made-up players if there are none; or reroll if they're tied",
	"/pl test tie - a made-up raider rolls the same total as the leader (the last copy's, with several)",
	"/pl test lootpity - random pity on the latest loot, for you and about half the made-up raiders who can roll on it",
	"/pl test loot [count] - loot items you're wearing, as if from a made-up boss: a new group on the Loot tab, which your group sees too",
	"/pl test tutorialloot - the test menu's loot: the same five items every time",
	"/pl test raider - show the window as a raider without officer powers sees it (again to switch back)",
	"/pl test capture [new] - how much the test capture has recorded, or start a new one",
	"/pl test trust <name> - count another player as an officer while in test mode, and let your test rolls reach the group while they're in it, to test with friends",
	"/pl test warn - add a warning, to see how one shows",
	"/pl test trade <item> - with a player targeted: a copy of <item> from your bags is awaiting trade to them",
	"/pl test owed <item> - with a player targeted: a copy of <item> is awaiting trade from them to you",
	"/pl test probe [item] - what the game says about loot methods, the minimap menu, specs and talents, your target and an item, to copy",
	"/pl test raid [players] [edge] - fill the Raid tab with made-up raiders (20, up to 40), some with roles unknown (edge: one of each kind); left-click fakes an inspect; again to empty it",
}

local fakes = {} -- made-up rollers: { id, name }
local raiders -- the made-up raiders (below): guid -> member, and in order, while there are any
local arriving = {} -- the made-up raiders' rolls still to come in, as tokens
local rolledFor = {} -- the rounds the made-up raiders have been given their rolls for, as "sid:round"
local pitied = {} -- the loot groups given pity, by key
local pityJobs -- the pity changes Give Pity still has to make, while it's at work
local swept = false -- the made-up raid's had Inspect Unknown run over it, to the end
local pageRaids = {} -- the test menu's other page's raid, put away (SwapRaid): [true] raider page, [false] officer
local viewed = false -- the window's been seen as a raider sees it
local officerRolls = {} -- the rolls the raider page's made-up officer started, by sid, to hand out once decided

local function InTestMode()
	if ns.IsTestMode() then return true end
	ns.Print(L.TEST_MSG_NEED_TEST_MODE)
end

local function EquippedItems()
	local items, seen = {}, {}
	for slot = 1, 19 do
		local item = GetInventoryItemID("player", slot)
		if item and not seen[item] then
			seen[item] = true
			items[#items + 1] = item
		end
	end
	return items
end

-- Up to `count` different items you're wearing, in a random order.
local function RandomItems(count)
	local items = EquippedItems()
	for i = #items, 2, -1 do
		local j = math.random(i)
		items[i], items[j] = items[j], items[i]
	end
	for i = #items, count + 1, -1 do items[i] = nil end
	return items
end

-- Test pity as an officer's change; greed rolls have none (4.8). The item's made-up raid and boss go straight into the
-- test table, so My pity can show its groups.
local function SetPity(id, item, pity, instance, boss, greed)
	if greed or pity <= 0 then return true end
	if instance and ns.ledger then ns.ledger:Learn(item, instance, boss) end
	local now = ns.ledger and ns.ledger:Pity(id, item) or 0
	if pity == now then return true end
	return ns.RecordChange(ns.NewChange({ op = "adjust", id = id, item = item, steps = (pity - now) / ns.PITY_STEP }))
end

local function RandomPity()
	return math.random(1, ns.PITY_MAX / ns.PITY_STEP) * ns.PITY_STEP
end

-- The made-up raid a made-up boss is in.
local function RaidOf(boss)
	for _, raid in ipairs(TEST_RAIDS) do
		for _, name in ipairs(raid[2]) do
			if name == boss then return raid[1] end
		end
	end
end

local function NextFake()
	local index = #fakes + 1
	local name = NAMES[(index - 1) % #NAMES + 1] .. (index > #NAMES and tostring(math.ceil(index / #NAMES)) or "")
	local fake = { id = ("Player-0-%08X"):format(index), name = name }
	fakes[index] = fake
	ns.RememberName(fake.id, name, CLASSES[math.random(#CLASSES)])
	return fake
end

local test = {}

-- Loot made in test mode is marked, so it can go without touching real loot (still awaiting trade, say).
local function DropTestLoot()
	local kept = {}
	for _, group in ipairs(ns.loot.groups) do
		if not group.test then kept[#kept + 1] = group end
	end
	if #kept == #ns.loot.groups then return end
	ns.loot.groups = kept
	ns.Fire("LOOT_CHANGED")
end

-- Why test mode can't be on here, in words, if it can't.
local BLOCKED = { instance = L.TEST_IN_RAID, raidgroup = L.TEST_IN_RAID_GROUP }
local TURNED_OFF = { instance = L.TEST_MSG_OFF_IN_RAID, raidgroup = L.TEST_MSG_OFF_IN_RAID_GROUP }

function ns.TestModeBlockedText()
	local why = ns.TestModeBlocked()
	return why and BLOCKED[why]
end

function test.on()
	local blocked = ns.TestModeBlockedText()
	if blocked then return ns.Print(blocked) end
	ns.saved.testMode = true
	ns.UpdateGuild()
	ns.StartCapture()
	ns.Print(L.TEST_MSG_ON)
	ns.Fire("SESSION_CHANGED")
end

-- Turning test mode off leaves nothing made in it behind: no test roll or writer, no test loot, no made-up raiders.
-- `quiet` leaves the message to the caller.
function test.off(_, quiet)
	ns.saved.testMode, ns.saved.testViewAsRaider = nil, nil
	ns.StopTestWriting()
	DropTestLoot()
	if raiders then
		test.forgetRaiders()
		ns.Fire("ROSTER_CHANGED")
	end
	ns.StopCapture()
	ns.UpdateGuild()
	if not quiet then ns.Print(L.TEST_MSG_OFF) end
	ns.Fire("SESSION_CHANGED")
end

-- Entering a raid instance, or joining a raid group, turns test mode off (5.5).
local function TurnOffInRaid()
	local why = ns.saved and ns.saved.testMode and ns.TestModeBlocked()
	if not why then return end
	test.off(nil, true)
	ns.Print(TURNED_OFF[why])
end
ns.On("PLAYER_ENTERING_WORLD", TurnOffInRaid)
ns.On("GROUP_ROSTER_UPDATE", TurnOffInRaid)

function test.reset()
	if not InTestMode() then return end
	ns.saved.ledger[ns.guild] = nil
	if ns.saved.log then ns.saved.log[ns.guild] = nil end
	ns.guild = nil
	fakes, arriving, pitied, pityJobs, viewed, officerRolls, rolledFor = {}, {}, {}, nil, false, {}, {}
	pageRaids = {}
	ns.StopTestWriting()
	DropTestLoot()
	test.forgetRaiders()
	ns.ForgetRoles()
	ns.UpdateGuild()
	ns.Fire("ROSTER_CHANGED")
	ns.Print(L.TEST_MSG_RESET)
end

function test.pity(args)
	if not InTestMode() then return end
	local count = tonumber(args[3]) or 1
	local name = tonumber(args[3]) and args[4] or args[3]
	local id = name and ns.FindPlayer(name) or UnitGUID("player")
	if not id then return ns.Print("Can't find " .. name .. " in your group or guild.") end
	local items = RandomItems(count)
	if not items[1] then return ns.Print("Wear some gear first; pity goes on items you're wearing.") end
	for _, item in ipairs(items) do
		local pity = RandomPity()
		local raid = TEST_RAIDS[math.random(#TEST_RAIDS)]
		local ok, err = SetPity(id, item, pity, raid[1], raid[2][math.random(#raid[2])])
		ns.Print(ok and ("%s: %s +%d"):format(ns.NameOf(id), ns.ItemLink(item), pity) or ("Couldn't set pity: " .. err))
	end
end

function test.roll(args)
	if not InTestMode() then return end
	local item = ns.ItemID(args[3]) or RandomItems(1)[1]
	if not item then return ns.Print("Wear some gear first, or give an item: /pl test roll <item>") end
	if not ns.AmWriter() then ns.ClaimWriter() end
	ns.StartRoll(item, tonumber(args[4]) or 1)
end

local function OpenRoll()
	local m = ns.live.mirror
	if m and (m.state == "open" or m.state == "reroll") then return m end
	ns.Print(L.TEST_MSG_NEED_ROLL:format(L.TAB_LOOT))
end

-- A made-up raider's roll, counted as the writer would count their /roll: in the first round, with their pity from the
-- test ledger and off-spec from their role on the Raid tab (a stand-in role if it's unknown, 4.6).
local function RaiderRolls(raider, roll)
	local m = ns.live.mirror
	local pity, offSpec, guessed = 0, false, nil
	if m.round == 1 and not m.greed then
		pity = ns.PityOf(raider.guid, m.item)
		offSpec, guessed = ns.IsOffSpec(raider.guid, m.item)
	end
	return ns.CountTestRoll(raider.guid, raider.name, roll, pity, offSpec or nil, guessed)
end

-- Whether a made-up raider can still roll in this round: they haven't rolled or passed, and in a reroll they're tied.
local function CanStillRoll(m, raider)
	local id = raider.guid
	if (m.rounds[m.round] and m.rounds[m.round][id]) or m.passed[id] == m.round then return false end
	if m.state == "reroll" then return m.contenders[id] == true end
	return ns.MayRollOn(id, m.item, m.greed)
end

-- The made-up raiders roll as a raid does: in the first round, most of those who can use the item (some don't want
-- it), and in a reroll, the tied ones; their rolls come in over a moment. Returns how many will roll.
local WANT_CHANCE = 0.7
-- Items everyone who can use them rolls on, nobody holding back: the test menu's axe, so both copies go to raiders.
local ALL_ROLL = { [6975] = true }
local ROLL_WAIT = 1 -- seconds before the first rolls come in
local ROLL_SPREAD = 2 -- seconds the rolls come in over, after that
local AT_ONCE = 0.3 -- of the rolls, the share that come in as soon as rolls do (always at least one)

local function RaidersRoll(m)
	rolledFor[m.sid .. ":" .. m.round] = true
	-- In the first round, one raider who could roll always holds back, so there's someone left to make a tie with.
	local rolling, held = {}, nil
	for _, raider in ipairs(raiders) do
		if CanStillRoll(m, raider) then
			if m.state == "reroll" then
				rolling[#rolling + 1] = raider
			elseif ALL_ROLL[m.item] then
				rolling[#rolling + 1] = raider
			elseif not held then
				held = raider
			elseif math.random() < WANT_CHANCE then
				rolling[#rolling + 1] = raider
			end
		end
	end
	local first = math.random(math.max(#rolling, 1))
	for i, raider in ipairs(rolling) do
		local token, round = {}, m.round
		arriving[token] = true
		local delay = ROLL_WAIT + ((i == first or math.random() < AT_ONCE) and 0 or math.random() * ROLL_SPREAD)
		C_Timer.After(delay, function()
			if not arriving[token] then return end
			arriving[token] = nil
			local now = ns.live.mirror
			if now == m and now.round == round and (now.state == "open" or now.state == "reroll") then
				RaiderRolls(raider, math.random(ns.ROLL_MIN, ns.ROLL_MAX))
			end
			ns.Fire("SESSION_CHANGED")
		end)
	end
	ns.Fire("SESSION_CHANGED")
	return #rolling
end

-- In test mode the made-up raiders roll by themselves: in a new roll, most of those who can (some don't want it), and
-- in a reroll, the tied ones; their rolls come in over a moment, some at once.
ns.Listen("ROLL_EVENT", function(kind, m)
	if (kind == "open" or kind == "reroll") and m and raiders and ns.IsTestMode() and ns.AmWriter() then RaidersRoll(m) end
end)

function test.rollers(args)
	if not InTestMode() then return end
	local m = OpenRoll()
	if not m then return end
	if raiders then
		local count = RaidersRoll(m)
		if count == 0 then return ns.Print(L.TEST_MSG_NOBODY_ROLLS) end
		if m.state == "reroll" then
			return ns.Print(count == 1 and L.TEST_MSG_REROLLING_ONE or L.TEST_MSG_REROLLING:format(count))
		end
		return ns.Print(count == 1 and L.TEST_MSG_ROLLING_ONE or L.TEST_MSG_ROLLING:format(count))
	end
	local counted = 0
	if m.state == "reroll" then
		for _, fake in ipairs(fakes) do
			if m.contenders[fake.id] and ns.CountTestRoll(fake.id, fake.name, math.random(1, ns.ROLL_MAX)) then
				counted = counted + 1
			end
		end
		return ns.Print(("%d made-up players rerolled."):format(counted))
	end
	for _ = 1, tonumber(args[3]) or 5 do
		local fake = NextFake()
		-- Half of them have waited for this item before.
		local pity = math.random() < 0.5 and math.random(1, ns.PITY_MAX / ns.PITY_STEP) * ns.PITY_STEP or 0
		if pity > 0 then SetPity(fake.id, m.item, pity, nil, nil, m.greed) end
		local offSpec = math.random() < OFF_SPEC_CHANCE or nil
		if ns.CountTestRoll(fake.id, fake.name, math.random(1, ns.ROLL_MAX), pity, offSpec) then counted = counted + 1 end
	end
	ns.Print(("%d made-up players rolled."):format(counted))
end

-- A made-up raider rolls the same total as the leader (with several copies, the last copy's), so the tie can be
-- seen: when the round closes, it's rerolled. Players on the same total with the same bonus are told apart by their
-- raw rolls instead (4.3), so a raider with the leader's bonus rolls the leader's number.
function test.tie()
	if not InTestMode() then return end
	local m = OpenRoll()
	if not m then return end
	if not raiders then return ns.Print(L.TEST_MSG_NEED_RAIDERS) end
	if m.state ~= "open" then return ns.Print(L.TEST_MSG_FIRST_ROUND) end
	local totals = {}
	for id, roll in pairs(m.rounds[1]) do
		local entrant = m.entrants[id]
		local bonus = ns.Bonus(entrant.pity or 0, entrant.offSpec)
		totals[#totals + 1] = { id = id, roll = roll, bonus = bonus, value = ns.EffectiveRoll(roll, bonus) }
	end
	if #totals < m.copies then
		return ns.Print(m.copies == 1 and L.TEST_MSG_TIE_NEED_ROLL or L.TEST_MSG_TIE_NEED_ROLLS:format(m.copies, m.copies))
	end
	table.sort(totals, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return a.roll > b.roll
	end)
	local cut = totals[m.copies]
	local candidates = {}
	for _, raider in ipairs(raiders) do
		if CanStillRoll(m, raider) then table.insert(candidates, math.random(#candidates + 1), raider) end
	end
	for _, raider in ipairs(candidates) do
		local pity, offSpec = 0, false
		if not m.greed then
			pity = ns.PityOf(raider.guid, m.item)
			offSpec = ns.IsOffSpec(raider.guid, m.item) or false
		end
		local bonus = ns.Bonus(pity, offSpec)
		local roll = cut.value - bonus
		if bonus == cut.bonus then
			roll = cut.roll
		elseif cut.value == ns.ROLL_MAX then
			roll = math.max(ns.ROLL_MAX - bonus, ns.ROLL_MIN)
		end
		if roll >= ns.ROLL_MIN and roll <= ns.ROLL_MAX and ns.EffectiveRoll(roll, bonus) == cut.value
			and RaiderRolls(raider, roll) then
			return ns.Print(L.TEST_MSG_TIED:format(
				ns.ColoredName(raider.guid), roll, cut.value, ns.ColoredName(cut.id, m.entrants[cut.id].name)))
		end
	end
	ns.Print(L.TEST_MSG_NO_TIE)
end

-- Pity on three of the latest loot's items at random, as if earlier raids had happened, never on Thunderfury (the
-- test menu's first item): nobody's waited on that one before. Those you can roll on come first, and you get some on
-- all three, so My Pity always shows three (even one your class can't use, if fewer than three are yours, as it's
-- only for show); about half the made-up raiders who can roll on each get some too. Each player's pity is different
-- on every item.
local PITY_CHANCE = 0.5
local PITY_ITEMS = 3
local NO_PITY = { [19019] = true }

-- Someone in the group, you or a made-up raider, who can roll on the item.
local function AnyoneCanRoll(item)
	if ns.MayRollOn(UnitGUID("player"), item) then return true end
	for _, raider in ipairs(raiders or {}) do
		if ns.MayRollOn(raider.guid, item) then return true end
	end
	return false
end

-- The items to give pity on: at random, but those you can roll on first, then those somebody else here can.
local function PityItems(group)
	local yours, raids, others = {}, {}, {}
	for _, entry in ipairs(group.items) do
		if not NO_PITY[entry.item] then
			local list = ns.MayRollOn(UnitGUID("player"), entry.item) and yours or AnyoneCanRoll(entry.item) and raids
				or others
			table.insert(list, math.random(#list + 1), entry)
		end
	end
	for _, list in ipairs({ raids, others }) do
		for _, entry in ipairs(list) do yours[#yours + 1] = entry end
	end
	for i = #yours, PITY_ITEMS + 1, -1 do yours[i] = nil end
	return yours
end

-- Each pity there is, in a random order, for one player to take from in turn.
local function PityValues()
	local values = {}
	for steps = 1, ns.PITY_MAX / ns.PITY_STEP do table.insert(values, math.random(#values + 1), steps * ns.PITY_STEP) end
	return values
end

-- Each change is signed and logged, so a big raid's dozens of them are made a few milliseconds' worth a frame rather
-- than all at once, which hitched the game.
local PITY_BUDGET = 4
local Clock = debugprofilestop or function() return GetTime() * 1000 end

function test.lootpity()
	if not InTestMode() or pityJobs then return end
	local group = ns.LatestLoot()
	if not group then return ns.Print(L.TEST_MSG_NEED_LOOT) end
	local raid, me, mine, theirs, counted = RaidOf(group.boss), UnitGUID("player"), 0, 0, {}
	local jobs = {} -- { player, item, pity }
	local values = {} -- each player's pity still to give, so none of theirs is the same twice
	local function Next(id)
		values[id] = values[id] or PityValues()
		return table.remove(values[id])
	end
	for _, entry in ipairs(PityItems(group)) do
		jobs[#jobs + 1] = { me, entry.item, Next(me) }
		mine = mine + 1
		local given = true
		-- About half the raiders who can roll on it; at least one, if nobody else has pity on it.
		local eligible = {}
		for _, raider in ipairs(raiders or {}) do
			if ns.MayRollOn(raider.guid, entry.item) then table.insert(eligible, math.random(#eligible + 1), raider) end
		end
		for i, raider in ipairs(eligible) do
			if math.random() < PITY_CHANCE or (i == #eligible and not given) then
				jobs[#jobs + 1] = { raider.guid, entry.item, Next(raider.guid) }
				given = true
				if not counted[raider.guid] then
					counted[raider.guid] = true
					theirs = theirs + 1
				end
			end
		end
	end
	pityJobs = jobs
	local function Work()
		if pityJobs ~= jobs then return end -- started over meanwhile
		local start = Clock()
		repeat
			local job = table.remove(jobs, 1)
			if job then SetPity(job[1], job[2], job[3], raid, group.boss) end
		until not jobs[1] or Clock() - start >= PITY_BUDGET
		if jobs[1] then return C_Timer.After(0, Work) end
		pityJobs = nil
		pitied[group.key] = true
		ns.Print(raiders and L.TEST_MSG_PITY_GIVEN_RAID:format(mine, theirs) or L.TEST_MSG_PITY_GIVEN:format(mine))
		ns.Fire("LOOT_CHANGED")
	end
	-- The My Pity tab straight away, filling in as the pity's given.
	ns.ShowWindow("pity")
	Work()
end

-- A made-up boss's loot (`loot` as Loot.lua lists it), on the Loot tab and shared as a master looter would.
local function DropLoot(loot, from)
	if not ns.AmWriter() then ns.ClaimWriter() end
	local raid = TEST_RAIDS[math.random(#TEST_RAIDS)]
	ns.SetLoot(loot, from or ns.PlayerName(), raid[2][math.random(#raid[2])], true)
	ns.LatestLoot().test = true
	ns.ShareLoot()
	ns.ShowWindow("loot")
end

function test.loot(args)
	if not InTestMode() then return end
	local items = RandomItems(tonumber(args[3]) or 3)
	if not items[1] then return ns.Print(L.TEST_MSG_NO_GEAR) end
	local loot = {}
	for i, item in ipairs(items) do
		loot[i] = { item = item, copies = math.random() < 0.2 and 2 or 1, boe = ns.IsBoE(item) or nil }
	end
	DropLoot(loot)
end

-- The test menu's loot, always the same five items in this order: a spread of rarities, classes and roles, with a
-- BoE among them; two of the axe drop, so two copies are rolled for (and the raid has the warriors to want them). The game may not have them loaded yet, and whether
-- one is BoE needs its data, so it waits for them (at most a couple of seconds, should one never load).
local TUTORIAL_LOOT = { 19019, 22478, 22512, 6975, 4454 }
local TUTORIAL_COPIES = { [6975] = 2 }
local ITEM_WAIT = 2
local lootToken

function test.tutorialloot(from)
	if not InTestMode() then return end
	local token = {}
	lootToken = token
	local waiting = #TUTORIAL_LOOT
	local function Drop()
		if lootToken ~= token or not ns.IsTestMode() then return end
		lootToken = nil
		local loot = {}
		for i, item in ipairs(TUTORIAL_LOOT) do
			loot[i] = { item = item, copies = TUTORIAL_COPIES[item] or 1, boe = ns.IsBoE(item) or nil }
		end
		DropLoot(loot, from)
	end
	if not (Item and Item.CreateFromItemID) then return Drop() end
	for _, id in ipairs(TUTORIAL_LOOT) do
		Item:CreateFromItemID(id):ContinueOnItemLoad(function()
			waiting = waiting - 1
			if waiting == 0 then Drop() end
		end)
	end
	C_Timer.After(ITEM_WAIT, Drop)
end

function test.raider()
	if not InTestMode() then return end
	ns.saved.testViewAsRaider = not ns.saved.testViewAsRaider or nil
	if ns.saved.testViewAsRaider then viewed = true end
	ns.Print(ns.saved.testViewAsRaider and L.TEST_MSG_AS_RAIDER_ON or L.TEST_MSG_AS_RAIDER_OFF)
	ns.Fire("SESSION_CHANGED")
end

function test.capture(args)
	if not InTestMode() then return end
	if args[3] == "new" then ns.StartCapture() end
	local count = ns.CaptureCount()
	ns.Print(count and ("The test capture has %d records. It's saved to PitifulLootCapture (WTF/Account/<account>/SavedVariables/PitifulLoot.lua) when you log out or /reload."):format(count)
		or "No capture is running; /pl test capture new starts one.")
end

function test.trust(args)
	if not InTestMode() then return end
	local name = args[3] and ns.ShortName(args[3])
	if not name then return ns.Print("/pl test trust <name>") end
	ns.saved.testOfficers[name] = not ns.saved.testOfficers[name] or nil
	ns.Print(("%s %s as an officer in test mode."):format(name, ns.saved.testOfficers[name] and "now counts" or "no longer counts"))
end

function test.warn()
	ns.Warn("This is a test warning. Click the sign to dismiss it.")
end

-- Your target's GUID, if it's another player whose GUID can be read.
local function TargetPlayer()
	if not UnitIsPlayer("target") then return nil end
	local guid, me = UnitGUID("target"), UnitGUID("player")
	if not canaccessvalue(guid) or not canaccessvalue(me) then return nil end
	if not guid or guid == me then return nil end
	return guid
end

-- Handing over with any one other player, grouped or not: a won item awaiting trade between you and your target.
-- `toThem`: you hold it and it's owed to them; otherwise they hold it and it's owed to you.
local function TestHandover(args, toThem)
	if not InTestMode() then return end
	local item = ns.ItemID(args[3])
	if not item then return ns.Print(("/pl test %s <item>, with the player targeted"):format(toThem and "trade" or "owed")) end
	local them, name = TargetPlayer(), ns.FullUnitName("target")
	if not them then return ns.Print("Target the player to trade with first.") end
	if not name then return ns.Print("Your target's name can't be read right now; try out of combat.") end
	ns.RememberName(them, name, select(2, UnitClass("target")))
	local winner = toThem and them or UnitGUID("player")
	ns.SetLoot({ { item = item, copies = 1 } }, toThem and ns.PlayerName() or name, "Test trade", true)
	ns.LatestLoot().test = true
	local entry = ns.LatestLoot().items[1]
	entry.status, entry.winners = "awarded", { winner }
	entry.handovers = { { id = winner, sid = ("test:%d:%d"):format(GetServerTime(), math.random(1000000)) } }
	ns.Fire("LOOT_CHANGED")
	ns.ShowWindow("loot")
	if not toThem then
		return ns.Print(("%s is awaiting trade from %s to you. Have them open a trade and put one in; Accept Loot Trades accepts it for you."):format(ns.ItemLink(item), ns.ColoredName(them)))
	end
	ns.Print(("%s is awaiting trade to %s. Left-click it on the Loot tab to open the trade, or have them open one with you."):format(ns.ItemLink(item), ns.ColoredName(them)))
	if not ns.HoldsItem(item) then ns.Print("You don't have one in your bags, so nothing will go into the trade.") end
end

function test.trade(args) TestHandover(args, true) end
function test.owed(args) TestHandover(args, false) end

-- Probing the client: values as text, with secret ones and errors said as such.
local function Text(...)
	local parts = {}
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if issecretvalue and issecretvalue(value) then
			parts[i] = "<secret>"
		elseif type(value) == "table" then
			local inner = {}
			for k, v in pairs(value) do inner[#inner + 1] = tostring(k) .. "=" .. Text(v) end
			table.sort(inner)
			parts[i] = "{" .. table.concat(inner, ", ") .. "}"
		else
			parts[i] = tostring(value)
		end
	end
	return table.concat(parts, ", ")
end

local function Try(f, ...)
	if type(f) ~= "function" then return "<not in this client>" end
	return (function(ok, ...)
		if not ok then return "<error: " .. tostring((...)) .. ">" end
		return Text(...)
	end)(pcall(f, ...))
end

-- A box to copy text from, as chat can't be copied: Ctrl+A then Ctrl+C.
local copyBox
local function ShowCopyBox(title, text)
	if not copyBox then
		copyBox = CreateFrame("Frame", "PitifulLootCopyBox", UIParent, "PortraitFrameTemplate")
		copyBox:SetSize(520, 420)
		copyBox:SetPoint("CENTER")
		copyBox:SetFrameStrata("DIALOG")
		copyBox:SetMovable(true)
		copyBox:EnableMouse(true)
		copyBox:RegisterForDrag("LeftButton")
		copyBox:SetScript("OnDragStart", copyBox.StartMoving)
		copyBox:SetScript("OnDragStop", copyBox.StopMovingOrSizing)
		copyBox:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Dice_02")
		table.insert(UISpecialFrames, "PitifulLootCopyBox")
		local scroll = CreateFrame("ScrollFrame", nil, copyBox, "ScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 16, -64)
		scroll:SetPoint("BOTTOMRIGHT", -30, 16)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetFontObject("ChatFontNormal")
		edit:SetWidth(460)
		edit:SetScript("OnEscapePressed", function() copyBox:Hide() end)
		scroll:SetScrollChild(edit)
		copyBox.Edit = edit
		local hint = copyBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		hint:SetPoint("TOPLEFT", 64, -38)
		hint:SetText("Ctrl+A then Ctrl+C to copy.")
	end
	copyBox:SetTitle(title)
	copyBox.Edit:SetText(text)
	copyBox:Show()
	copyBox.Edit:SetFocus()
	copyBox.Edit:HighlightText()
end

-- What the client says about everything the beta checks are unsure of, in one place to copy: the loot methods
-- (is master loot there?), the minimap's addons menu, specs, talents and roles, your target's inspected spec and
-- talents, and an item.
function test.probe(args)
	local lines = { "Pitiful Loot probe, " .. date("%Y-%m-%d %H:%M"), "Client: " .. Try(GetBuildInfo) }
	local function Add(label, value) lines[#lines + 1] = label .. ": " .. value end

	local names = {}
	for name, value in pairs(Enum.LootMethod or {}) do names[value] = name end
	local available = {}
	local ok, methods = pcall(C_PartyInfo.GetAvailableLootMethods)
	for _, method in ipairs(ok and type(methods) == "table" and methods or {}) do
		available[#available + 1] = names[method] or tostring(method)
	end
	Add("Loot methods available", ok and table.concat(available, ", ") or "<error>")
	Add("Master loot available", Try(C_PartyInfo.IsLootMethodAvailable, Enum.LootMethod and Enum.LootMethod.Masterlooter))
	Add("Current loot method", Try(C_PartyInfo.GetLootMethod))

	local menu = AddonCompartmentFrame
	if menu then
		local listed = false
		for _, data in ipairs(menu.registeredAddons or {}) do
			if type(data.text) == "string" and data.text:find("Pitiful Loot", 1, true) then listed = true end
		end
		Add("Addons menu", ("exists, shown %s, %d addons, Pitiful Loot listed %s, Minimap Button option %s"):format(
			Try(menu.IsShown, menu), #(menu.registeredAddons or {}), tostring(listed), tostring(ns.settings.minimapButton)))
	else
		Add("Addons menu", "AddonCompartmentFrame doesn't exist")
	end
	local minimapButton = ns.MinimapButton and ns.MinimapButton()
	Add("Minimap button", minimapButton and ("shown %s, parent %s, option %s"):format(Try(minimapButton.IsShown, minimapButton),
		Try(function() local parent = minimapButton:GetParent() return parent and parent:GetName() end), tostring(ns.settings.minimapButton))
		or "not made")

	local found, index = pcall(C_SpecializationInfo.GetSpecialization)
	if not found then index = nil end
	Add("Your spec index", Text(index))
	Add("Your spec info", index and Try(C_SpecializationInfo.GetSpecializationInfo, index) or "-")
	Add("Specs for your class", Try(C_SpecializationInfo.GetNumSpecializationsForClassID, select(3, UnitClass("player"))))
	Add("Spec selection enabled", Try(C_SpecializationInfo.IsSpecSelectionEnabled))
	Add("Your assigned role", Try(UnitGroupRolesAssigned, "player"))
	-- The talents the role guess reads, from the trait tree: how many could be read, and those taken.
	local function Talents(inspect)
		local talents = ns.ReadTalents(inspect)
		if not talents then return "can't be read" end
		local list = {}
		for name in pairs(talents.taken) do list[#list + 1] = name end
		table.sort(list)
		local trees = {}
		for _, tree in ipairs(talents.trees or {}) do
			trees[#trees + 1] = ("%s (last node %s%s)"):format(Text(tree.name), Text(tree.capstone), tree.taken and ", taken" or "")
		end
		return ("%d read, taken: %s; trees: %s"):format(talents.read, list[1] and table.concat(list, ", ") or "none",
			trees[1] and table.concat(trees, ", ") or "can't be told apart")
	end
	Add("Spec groups", ("active %s of %s, talent config %s"):format(Try(C_SpecializationInfo.GetActiveSpecGroup), Try(GetNumSpecGroups),
		Try(C_ClassTalents.GetActiveConfigID)))
	Add("Your talents", Talents(false))
	Add("Role from talents", Text(ns.MyRole()))
	Add("Profile", Text(ns.database:GetCurrentProfile()))

	local item = ns.ItemID(args[3])
	if item then
		Add("Item", ns.ItemLink(item) .. " (" .. item .. ")")
		Add("Item type", Try(C_Item.GetItemInfoInstant, item))
		Add("Item spec list", Try(C_Item.GetItemSpecInfo, item))
		local _, link = C_Item.GetItemInfo(item)
		Add("Item stats", link and Try(C_Item.GetItemStats, link) or "<not loaded yet; probe again>")
		local tip = C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(item)
		for i, line in ipairs(tip and tip.lines or {}) do
			Add("Tooltip " .. i, Text(line.leftText) .. (line.rightText and ("  |  " .. Text(line.rightText)) or ""))
		end
	end

	local function Finish()
		local text = table.concat(lines, "\n")
		ns.Capture("probe", text)
		ns.LastProbe = text
		ShowCopyBox("Pitiful Loot probe", text)
	end
	if not TargetPlayer() then return Finish() end
	Add("Target", Try(UnitName, "target") .. " (" .. Try(UnitClass, "target") .. ")")
	Add("Target's assigned role", Try(UnitGroupRolesAssigned, "target"))
	if CanInspect("target") then NotifyInspect("target") end
	ns.Print("Inspecting your target; the probe opens in 2 seconds.")
	C_Timer.After(2, function()
		local spec = C_SpecializationInfo.GetInspectSpecialization and select(2, pcall(C_SpecializationInfo.GetInspectSpecialization, "target"))
		Add("Target's inspected spec", Text(spec))
		Add("That spec's info", Try(GetSpecializationInfoByID, spec))
		Add("Target's talents", ("valid inspect data %s; %s"):format(Try(C_Traits.HasValidInspectData), Talents(true)))
		Finish()
	end)
end

-- Made-up raiders for the Raid tab, after you in group 1: every class, roles from each source, and some unknown,
-- so a full raid can be seen on your own. With "edge", the first of them are one of each case where the fallback
-- role is used: never inspected, each way an inspect can fail, a capstone that leaves two roles, and talents with no
-- capstone. Left-clicking one fakes an inspect, going through those outcomes in turn and then finding their role.
-- They're on the Raid tab, and roll when /pl test rollers says so, with the role it shows them in.
local SURNAMES = { "Ash", "Brook", "Crane", "Dale", "Frost", "Hale", "Marsh", "Stone", "Thorne", "Vale" }
local RAID_ROLES = { "TANK", "HEALER", "DAMAGER", false, "DAMAGER" } -- false: unknown
local RAID_SOURCES = { "raid", "talents", "inspect" }
-- Class and reason for each edge case (no reason: never inspected).
local EDGE_CASES = {
	{ "WARRIOR" }, { "PRIEST", "far" }, { "PALADIN", "noreply" }, { "DRUID", "unreadable" },
	{ "DRUID", "ambiguous" }, { "SHAMAN", "ambiguous" }, { "PALADIN", "nocapstone" },
}
-- What a fake inspect finds, in turn; ambiguous only for classes whose capstone can be.
local FAKE_OUTCOMES = { "far", "noreply", "unreadable", "ambiguous", "nocapstone", "found" }
local FAKE_INSPECT_TIME = 1.5
local AMBIGUOUS_CLASSES = { DRUID = true, SHAMAN = true }
-- The test menu's raid: five raiders whose roles are unknown, to learn from (5.5). Three haven't been looked at yet,
-- one couldn't be inspected, and one has talents an inspect can't settle; the first four are found by inspecting
-- them, and the last has to be set by hand. Each is { place in the raid, class, role inspecting finds, why unknown }.
local TUTORIAL_RAID_MIN = 10
local TUTORIAL_CASES = {
	{ 3, "PALADIN", "HEALER" }, { 5, "PRIEST", "HEALER" }, { 7, "WARRIOR", "TANK" },
	{ 8, "DRUID", "TANK", { "far", "noreply", "unreadable" } },
	{ 10, "SHAMAN", nil, { "ambiguous", "nocapstone" } },
}
-- Warriors, with their roles known, so two copies of the menu's axe always have takers, whatever the raid's size.
local TUTORIAL_WARRIORS = { [4] = true, [9] = true }
local real = {
	GroupMembers = ns.GroupMembers, GroupMember = ns.GroupMember, RoleInfo = ns.RoleInfo, RoleReason = ns.RoleReason,
	IsInspecting = ns.IsInspecting, InspectRaider = ns.InspectRaider, InspectUnknown = ns.InspectUnknown,
	IsSweeping = ns.IsSweeping, RoleOf = ns.RoleOf, OfferTrade = ns.OfferTrade,
}
local fakeSweep -- the made-up raiders a fake "Inspect Unknown" is still to try, while it's on

function ns.GroupMembers()
	local members = real.GroupMembers()
	if not raiders then return members end
	local all = {}
	for _, member in ipairs(members) do all[#all + 1] = member end
	for _, raider in ipairs(raiders) do all[#all + 1] = raider end
	return all
end

function ns.GroupMember(key)
	return raiders and key and raiders[key] or real.GroupMember(key)
end

function ns.RoleInfo(guid, ignoreOfficer)
	local raider = raiders and raiders[guid]
	if raider and raider.role ~= nil then
		local role, source, by = real.RoleInfo(guid, ignoreOfficer)
		if source == "officer" or source == "class" then return role, source, by end
		if raider.role then return raider.role, raider.source end
		return nil
	end
	return real.RoleInfo(guid, ignoreOfficer)
end

-- The role a made-up raider rolls as: the one the Raid tab shows, or their class's fallback role while it's unknown.
function ns.RoleOf(guid)
	local raider = raiders and raiders[guid]
	if not raider then return real.RoleOf(guid) end
	local role = ns.RoleInfo(guid)
	if role then return role end
	return ns.FallbackRole(raider.class, raider.why), true
end

function ns.RoleReason(guid)
	local raider = raiders and raiders[guid]
	if raider then return raider.why end
	return real.RoleReason(guid)
end

function ns.IsInspecting(guid)
	local raider = raiders and raiders[guid]
	if raider then return raider.inspecting == true end
	return real.IsInspecting(guid)
end

-- A fake inspect: the raider's next outcome, after a moment (at once if they're "too far away"). A failure keeps a
-- role that was known, and a role found replaces one an officer set, as a real one does. `onDone(found)` is for a
-- fake sweep, which doesn't print each one.
function ns.InspectRaider(member, onDone)
	local raider = raiders and raiders[member.guid]
	if not raider then return real.InspectRaider(member) end
	if raider.inspecting or not ns.RoleChoices(raider) then return end
	-- The test menu's raiders always find the same; the others go through every outcome in turn.
	local outcome = raider.finds
	if not outcome then
		repeat
			raider.next = (raider.next or 0) % #FAKE_OUTCOMES + 1
		until FAKE_OUTCOMES[raider.next] ~= "ambiguous" or AMBIGUOUS_CLASSES[raider.class]
		outcome = FAKE_OUTCOMES[raider.next]
	end
	local function Finish()
		raider.inspecting = nil
		local name = ns.ColoredName(raider.guid, raider.name)
		if outcome == "found" then
			local choices = ns.RoleChoices(raider)
			local role = raider.trueRole or (choices.HEALER and "HEALER" or "TANK")
			raider.role, raider.source, raider.why = role, "inspect", nil
			if not onDone and select(2, ns.RoleInfo(raider.guid)) == "officer" then ns.SetRole(raider.guid, nil) end
			if not onDone then ns.Print(L["TALENTS_SAY_" .. raider.role]:format(name)) end
		else
			raider.why = outcome
			if raider.role == nil then raider.role = false end
			if not onDone then ns.Print(("%s: %s"):format(name, (ns.UNKNOWN_REASONS[outcome]:gsub("\n", " ")))) end
		end
		ns.Fire("ROLES_CHANGED")
		if onDone then onDone(outcome == "found") end
	end
	if outcome == "far" then return Finish() end
	raider.inspecting = true
	ns.Fire("ROLES_CHANGED")
	C_Timer.After(FAKE_INSPECT_TIME, Finish)
end

-- A fake "Inspect Unknown": each made-up raider whose role is unknown gets the next fake inspect, in turn.
function ns.InspectUnknown()
	if not raiders then return real.InspectUnknown() end
	if fakeSweep then return end
	local list = {}
	fakeSweep = list
	for _, member in ipairs(ns.UnknownRaiders()) do
		if raiders[member.guid] then list[#list + 1] = member end
	end
	local tried, found = #list, 0
	local function Next(gotOne)
		if fakeSweep ~= list then return end -- the raid's been swapped for the other page's
		if gotOne then found = found + 1 end
		local raider = fakeSweep and table.remove(fakeSweep, 1)
		if raider then return ns.InspectRaider(raider, Next) end
		fakeSweep, swept = nil, true
		ns.Fire("ROLES_CHANGED")
		ns.Print(L.SWEEP_DONE:format((tried == 1 and L.SWEEP_RAIDER or L.SWEEP_RAIDERS):format(tried),
			(found == 1 and L.SWEEP_ROLE or L.SWEEP_ROLES):format(found)))
	end
	ns.Fire("ROLES_CHANGED")
	Next()
end

function ns.IsSweeping()
	if raiders then return fakeSweep ~= nil end
	return real.IsSweeping()
end

-- Roles set by hand on made-up raiders go with them, as the next raid's are the same players again.
-- Trading with a made-up raider, as if the raid were real: the trade goes through at once, handing over every copy
-- you owe them, as a finished trade does (Trades.lua).
function ns.OfferTrade(id)
	local raider = raiders and raiders[id]
	if not raider then return real.OfferTrade(id) end
	local items = {}
	for _, pending in ipairs(ns.PendingTrades()) do
		if pending.id == id then
			items[#items + 1] = ns.ItemLink(pending.item)
			ns.MarkTraded(pending.sid, id)
		end
	end
	if items[1] then ns.Print(L.TEST_MSG_TRADED:format(table.concat(items, ", "), ns.ColoredName(id, raider.name))) end
end

function test.forgetRaiders()
	for _, raider in ipairs(raiders or {}) do
		if ns.saved and ns.saved.roleOverrides then ns.saved.roleOverrides[raider.guid] = nil end
	end
	raiders, fakeSweep, arriving, swept = nil, nil, {}, false
end

local function EmptyRaid()
	test.forgetRaiders()
	ns.Print(L.TEST_MSG_RAID_GONE)
	ns.Fire("ROSTER_CHANGED")
end

-- `count` players in all, you included. `edge`: the first of them are one of each kind of unknown role; `tutorial`:
-- the test menu's raid, with its five unknown roles (TUTORIAL_CASES) and every other role known; `known`: every role
-- known (the raider page's raid).
local function FillRaid(count, edge, tutorial, quiet, known)
	local least = tutorial and TUTORIAL_RAID_MIN or edge and #EDGE_CASES + 1 or 2
	count = math.max(math.min(math.floor(count), 40), least)
	local lesson = {}
	if tutorial then
		for _, case in ipairs(TUTORIAL_CASES) do lesson[case[1]] = case end
	end
	raiders = {}
	for i = 2, count do
		local case = edge and EDGE_CASES[i - 1]
		local taught = lesson[i]
		local class = taught and taught[2] or case and case[1] or tutorial and TUTORIAL_WARRIORS[i] and "WARRIOR"
			or CLASSES[(i * 4) % #CLASSES + 1]
		local guid = ("Player-0-RAID%04d"):format(i)
		local raider = {
			guid = guid, unit = "player", class = class, subgroup = math.ceil(i / 5),
			name = NAMES[(i - 1) % #NAMES + 1] .. " " .. SURNAMES[(i - 1) % #SURNAMES + 1],
		}
		if taught then
			local whys = taught[4]
			raider.role, raider.trueRole = false, taught[3]
			raider.why = whys and whys[math.random(#whys)] or nil
			-- Inspecting finds the role, unless the talents themselves leave it open.
			raider.finds = (raider.why == "ambiguous" or raider.why == "nocapstone") and raider.why or "found"
		elseif case then
			raider.role, raider.why = false, case[2]
		elseif ns.RoleChoices(raider) then
			-- Classes with a choice of roles get one from the list, from a source in turn, or none (but not in the
			-- test menu's raid, whose unknown roles are its lesson).
			local role = RAID_ROLES[i % #RAID_ROLES + 1]
			if role == false and (tutorial or known) then role = "DAMAGER" end
			if role and not ns.RoleChoices(raider)[role] then role = "DAMAGER" end
			raider.role, raider.source = role, role and RAID_SOURCES[i % #RAID_SOURCES + 1] or nil
		end
		raiders[#raiders + 1] = raider
		raiders[guid] = raider
		ns.RememberName(guid, raider.name, class)
	end
	local said = edge and L.TEST_MSG_RAID_FILLED_UNKNOWN or L.TEST_MSG_RAID_FILLED
	if not quiet then
		ns.Print(said:format(count - 1, L.TAB_RAID))
		ns.ShowWindow("raid")
	end
	ns.Fire("ROSTER_CHANGED")
end

function test.raid(args)
	if not InTestMode() then return end
	if raiders then return EmptyRaid() end
	local count, edge = 20, false
	for i = 3, #args do
		if args[i]:lower() == "edge" then edge = true else count = tonumber(args[i]) or count end
	end
	FillRaid(count, edge)
end

function test.help()
	ns.Print("Test mode is " .. (ns.IsTestMode() and "on." or "off."))
	for _, line in ipairs(HELP) do ns.Print(line) end
end

-- The raider page's made-up officer (TestMenu.lua): shares a boss's loot (from a raid of its own, if there isn't one),
-- starts a roll on each item in turn, top to bottom, and hands each out a moment after it's decided, as an officer
-- running the loot would.
local RAIDER_PAGE_RAID = 20
local CLOSE_DELAY = 1 -- seconds after everyone's rolled that the made-up officer closes the round
local raiderPage = false -- the test menu's raider page is on show
local closing -- the roll and round the made-up officer is about to close, as "sid:round"

local function TestOfficer()
	return raiders and raiders[1]
end

-- The made-up officer on the raider page: their GUID and name, which the window and raid chat show as the writer's
-- (Session.lua), though you're the writer underneath.
function ns.TestOfficer()
	local officer = raiderPage and ns.IsTestMode() and TestOfficer()
	if officer then return officer.guid, officer.name end
end

local function NextItem()
	local group = ns.LatestLoot()
	for _, entry in ipairs(group and group.items or {}) do
		if entry.status == "waiting" and #entry.winners < entry.copies then return entry end
	end
end

local function ShareLoot()
	if not InTestMode() then return end
	if not raiders then FillRaid(RAIDER_PAGE_RAID, false, false, true, true) end
	test.tutorialloot(TestOfficer().name)
end

local function StartNextRoll()
	local entry = InTestMode() and NextItem()
	if not entry then return end
	if not ns.AmWriter() then ns.ClaimWriter() end
	ns.StartRoll(entry.item, entry.copies - #entry.winners)
	local m = ns.live.mirror
	if m and m.state == "open" then officerRolls[m.sid] = true end
end

-- Whether you're done in this round: you've rolled or passed, or you can't take part.
local function YouAreDone(m)
	local me = UnitGUID("player")
	if (m.rounds[m.round] and m.rounds[m.round][me]) or m.passed[me] == m.round then return true end
	if m.state == "reroll" then return not m.contenders[me] end
	return not ns.MayRollOn(me, m.item, m.greed)
end

-- Once every raider who's rolling has, and you have too, the officer closes the round a moment later.
ns.Listen("SESSION_CHANGED", function()
	local m = ns.live.mirror
	if not (m and officerRolls[m.sid] and (m.state == "open" or m.state == "reroll") and ns.AmWriter()) then return end
	-- Only once the raiders' rolls for this round have been set going (the window can be told of a new round before
	-- they are) and have all come in.
	local key = m.sid .. ":" .. m.round
	if not rolledFor[key] or next(arriving) or not YouAreDone(m) then return end
	if closing == key then return end
	closing = key
	C_Timer.After(CLOSE_DELAY, function()
		if ns.live.mirror == m and closing == key and m.round .. "" == key:match("(%d+)$")
			and (m.state == "open" or m.state == "reroll") then
			ns.CloseRound()
		end
	end)
end)

-- And hands it out as soon as it's decided.
ns.Listen("ROLL_EVENT", function(kind, m)
	if kind ~= "decided" or not (m and officerRolls[m.sid]) then return end
	C_Timer.After(0, function()
		if ns.live.mirror ~= m or m.state ~= "decided" or not ns.AmWriter() then return end
		if m.winners[1] then
			ns.Award()
		elseif ns.IsBoE(m.item) then
			ns.KeepToSell()
		else
			ns.Disenchant()
		end
	end)
end)

-- Each page of the test menu has a raid of its own: the officer page's (with its lesson in unknown roles) and the
-- raider page's (every role known). Switching pages puts one away, with whether it's been swept and the roles set by
-- hand on it, and brings back the other, if it's been made. Both use the same GUIDs, so their names are told again.
local function SwapRaid(toRaider)
	local overrides = ns.saved.roleOverrides
	local leaving = raiders and { raiders = raiders, swept = swept, overrides = {} }
	for _, raider in ipairs(raiders or {}) do
		leaving.overrides[raider.guid] = overrides[raider.guid]
		overrides[raider.guid] = nil
	end
	local coming = pageRaids[toRaider]
	pageRaids[not toRaider], pageRaids[toRaider] = leaving, nil
	raiders, swept, fakeSweep, arriving = coming and coming.raiders, coming and coming.swept or false, nil, {}
	if coming then
		for guid, override in pairs(coming.overrides) do overrides[guid] = override end
		for _, raider in ipairs(raiders) do ns.RememberName(raider.guid, raider.name, raider.class) end
	end
	ns.Fire("ROSTER_CHANGED")
end

-- The raider page on show, or not: the window as a raider sees it, the made-up officer's name as the writer's, and
-- the page's own raid. Unlike /pl test raider, it says nothing, and doesn't count as having looked (officer page
-- step 7).
local function SetRaiderPage(on)
	on = on == true
	if on ~= raiderPage then SwapRaid(on) end
	raiderPage = on
	ns.saved.testViewAsRaider = on or nil
	ns.Fire("SESSION_CHANGED")
end

-- Runs fn with a quiet made-up raid of `count` in place of the current one, then puts the current one back (for the
-- performance tests, Perf.lua). Returns whether it ran: only in test mode.
local function WithRaid(count, fn)
	if not ns.IsTestMode() then return false end
	local was, wasSwept, wasSweep = raiders, swept, fakeSweep
	FillRaid(count, false, false, true)
	local ok, err = pcall(fn)
	raiders, swept, fakeSweep = was, wasSwept, wasSweep
	for _, raider in ipairs(raiders or {}) do ns.RememberName(raider.guid, raider.name, raider.class) end
	ns.Fire("ROSTER_CHANGED")
	if not ok then error(err, 0) end
	return true
end

-- What the test menu (TestMenu.lua) uses.
ns.Test = {
	WithRaid = WithRaid,
	On = test.on, Off = test.off, Reset = test.reset, ToggleRaider = test.raider,
	FillRaid = function(count) if InTestMode() then FillRaid(count, false, true) end end,
	RAID_MIN = TUTORIAL_RAID_MIN,
	EmptyRaid = function() if InTestMode() then EmptyRaid() end end,
	HasRaiders = function() return raiders ~= nil end,
	-- Whether the raid's had Inspect Unknown run over it, to the end.
	Swept = function() return raiders ~= nil and swept end,
	-- Whether the window's been seen as a raider sees it.
	ViewedAsRaider = function() return viewed end,
	Loot = function() test.tutorialloot() end,
	GivePity = test.lootpity,
	-- Whether a test boss has dropped its loot.
	Looted = function()
		for _, group in ipairs(ns.loot.groups) do
			if group.test then return true end
		end
		return false
	end,
	-- Whether Give Pity's at work.
	GivingPity = function() return pityJobs ~= nil end,
	-- Whether the latest loot has been given pity.
	GavePity = function()
		local group = ns.LatestLoot()
		return group ~= nil and pitied[group.key] == true
	end,
	RaidersRoll = function() test.rollers({}) end,
	MakeTie = test.tie,
	RollsArriving = function() return next(arriving) ~= nil end,
	ShareLoot = ShareLoot,
	StartNextRoll = StartNextRoll,
	NextItem = NextItem,
	SetRaiderPage = SetRaiderPage,
}

ns.commands.test = function(args)
	if not args[2] then return ns.ToggleTestMenu() end
	local command = test[args[2]:lower()] or test.help
	command(args)
end
