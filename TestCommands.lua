local _, ns = ...

-- TEMPORARY: commands for trying the addon out in game, alone or with friends. Remove this file (and its TOC line)
-- before release.
--
-- Everything runs in test mode, which keeps its own ledger, counts you as an officer, lets you be the writer without
-- a group, and sends and accepts no ledger sync, so nothing done here reaches the guild's real ledger. Live roll
-- messages still go to your group, so friends in test mode who trust you (/pl test trust <you>) see your rolls.
-- On your own, the writer's raid chat and raid warnings are previewed as the raid would see them (Session.lua).

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
	"/pl test on | off - test mode: a separate ledger, you count as an officer, no ledger sync",
	"/pl test reset - empty the test ledger",
	"/pl test pity [count] [name] - random pity on random items you're wearing, from made-up raids (for someone else with a name)",
	"/pl test roll [item] [copies] - become the writer and start a roll (a random item you're wearing if none is given)",
	"/pl test rollers [count] - made-up players roll in the open roll, or reroll if they're tied",
	"/pl test loot [count] - loot items you're wearing, as if from a made-up boss: a new group on the Loot tab, which your group sees too",
	"/pl test member - show the window as a member without officer powers sees it (again to switch back)",
	"/pl test capture [new] - how much the test capture has recorded, or start a new one",
	"/pl test trust <name> - count another player as an officer while in test mode, to test with friends",
	"/pl test warn - add a warning, to see how one shows",
}

local fakes = {} -- made-up rollers: { id, name }

local function InTestMode()
	if ns.IsTestMode() then return true end
	ns.Print("Turn test mode on first: /pl test on")
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

-- greed sets the greed-roll counter (4.8), which a greed roll's pity comes from.
local function SetPity(id, item, pity, instance, boss, greed)
	return ns.AppendEntry({
		type = "adjust", id = id, item = item, pity = pity, time = GetServerTime(), by = ns.PlayerName(),
		instance = instance, boss = boss, greed = greed or nil,
	})
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

function test.on()
	ns.saved.testMode = true
	ns.UpdateGuild()
	ns.StartCapture()
	ns.Print("Test mode is on. You're using a separate test ledger, count as an officer and can be the writer on your own. Nothing reaches the guild's ledger. On your own, raid chat and raid warnings are shown to you as the raid would see them. /pl test for the commands.")
	ns.Fire("SESSION_CHANGED")
end

function test.off()
	ns.saved.testMode, ns.saved.testViewAsMember = nil, nil
	ns.StopCapture()
	ns.UpdateGuild()
	ns.Print("Test mode is off; back to the guild's ledger.")
	ns.Fire("SESSION_CHANGED")
end

function test.reset()
	if not InTestMode() then return end
	ns.saved.ledgers[ns.guild] = nil
	ns.ledgers[ns.guild] = nil
	ns.guild = nil
	fakes = {}
	ns.UpdateGuild()
	ns.Print("The test ledger is empty.")
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
		local pity = math.random(1, ns.PITY_MAX / ns.PITY_STEP) * ns.PITY_STEP
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

function test.rollers(args)
	if not InTestMode() then return end
	local m = ns.live.mirror
	if not m or (m.state ~= "open" and m.state ~= "reroll") then
		return ns.Print("Start a roll first: /pl test roll")
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

function test.loot(args)
	if not InTestMode() then return end
	local items = RandomItems(tonumber(args[3]) or 3)
	if not items[1] then return ns.Print("Wear some gear first; the test loot is made from items you're wearing.") end
	if not ns.AmWriter() then ns.ClaimWriter() end
	local loot = {}
	for i, item in ipairs(items) do
		loot[i] = { item = item, copies = math.random() < 0.2 and 2 or 1, boe = ns.IsBoE(item) or nil }
	end
	local raid = TEST_RAIDS[math.random(#TEST_RAIDS)]
	ns.SetLoot(loot, ns.PlayerName(), raid[2][math.random(#raid[2])], true)
	ns.ShareLoot()
end

function test.member()
	if not InTestMode() then return end
	ns.saved.testViewAsMember = not ns.saved.testViewAsMember or nil
	ns.Print(ns.saved.testViewAsMember
		and "The window now shows what a member without officer powers sees. You're still the writer underneath; /pl test member switches back."
		or "The window shows your officer controls again.")
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

function test.help()
	ns.Print("Test mode is " .. (ns.IsTestMode() and "on." or "off."))
	for _, line in ipairs(HELP) do ns.Print(line) end
end

ns.commands.test = function(args)
	local command = test[(args[2] or "help"):lower()] or test.help
	command(args)
end
