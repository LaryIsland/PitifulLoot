local _, ns = ...

-- The options, shown on the window's Options tab (UI.lua). They're account-wide, the same for every character.
-- Officer options only matter to the writer; the Options tab hides them unless an officer asks to see them.

local function Seconds(value)
	return ("%d sec"):format(value)
end

-- What auto-roll does: nothing, roll for you in rerolls only, or in every roll you can take part in.
ns.AUTO_ROLL = { OFF = 0, REROLLS = 1, ALL = 2 }

ns.OPTIONS = {
	{ section = "Announcements", officer = true },
	{ key = "announce", officer = true, kind = "checkbox", name = "Announce in Raid Chat",
		tooltip = "As the writer, post each roll, tie and result to raid chat, so players without the addon can follow along." },
	{ key = "raidWarning", officer = true, kind = "checkbox", name = "Use Raid Warnings",
		tooltip = "As the writer, post the start of each roll, ties and results as raid warnings, if you're the raid leader or an assistant. Breakdowns still go to raid chat." },
	{ section = "Running Rolls", officer = true },
	{ key = "rollTime", officer = true, kind = "slider", name = "Roll Time", min = 10, max = 120, step = 5, format = Seconds,
		tooltip = "How long players have to /roll when a roll starts." },
	{ key = "rerollTime", officer = true, kind = "slider", name = "Reroll Time", min = 10, max = 60, step = 5, format = Seconds,
		tooltip = "How long tied players have to /roll again." },
	{ key = "minQuality", officer = true, kind = "dropdown", name = "Loot Quality",
		choices = { { 2, "Uncommon" }, { 3, "Rare" }, { 4, "Epic" }, { 5, "Legendary" } },
		tooltip = "The lowest item quality listed from the loot window for rolling." },
	{ key = "autoAward", officer = true, kind = "checkbox", name = "Award Automatically",
		tooltip = "As the writer, award each roll as soon as it's decided, without clicking Award." },
	{ section = "Rolling" },
	{ key = "autoRoll", kind = "dropdown", name = "Auto-roll",
		choices = { { ns.AUTO_ROLL.OFF, "Off" }, { ns.AUTO_ROLL.REROLLS, "Rerolls only" }, { ns.AUTO_ROLL.ALL, "Every roll" } },
		tooltip = "Roll for you. Rerolls only: when you're tied, roll again straight away. Every roll: also roll a few seconds after any roll you can take part in starts, unless you pass first." },
	{ section = "Trading" },
	{ key = "autoAcceptTrade", kind = "checkbox", name = "Accept Loot Trades",
		tooltip = "Click Trade for you when a trade only hands over won loot: either you give only items owed to the other player and get nothing back, or you get only items you've won and give nothing. No gold either way. Any other trade waits for you." },
	{ section = "Window" },
	{ key = "autoShow", kind = "checkbox", name = "Show When I Can Roll",
		tooltip = "Open the window on the Roll tab whenever a roll starts that you can take part in." },
	{ key = "autoShowLoot", kind = "checkbox", name = "Show New Loot",
		tooltip = "Open the window on the Loot tab when a boss's loot is added." },
	{ key = "hideUnrollable", kind = "checkbox", name = "Hide Loot I Can't Roll On",
		tooltip = "Leave items your class can't use, and later drops of items you've won, off the Loot tab, and don't open the window for loot that's all like that. The copy you win stays. The writer always sees everything." },
	{ key = "pityByBoss", kind = "checkbox", name = "Group My Pity by Boss",
		tooltip = "On the My pity tab, group items by the boss that drops them, inside each raid." },
	{ key = "hideWon", kind = "checkbox", name = "Hide Won Items",
		tooltip = "Leave the items you've won off the My pity tab." },
	{ key = "minimapButton", kind = "checkbox", name = "Minimap Button",
		tooltip = "List Pitiful Loot in the addons menu on the minimap: left-click opens the window, right-click its options. /pl opens the window either way." },
}

-- Changing an option.
function ns.SetOption(key, value)
	ns.settings[key] = value
	ns.Fire("SETTINGS_CHANGED", key)
	if ns.RefreshWindow then ns.RefreshWindow() end
end

function ns.OpenOptions()
	ns.ShowWindow("options")
end
