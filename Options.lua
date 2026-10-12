local _, ns = ...

-- The options, shown on the window's Options tab (UI.lua). They're account-wide, the same for every character.
-- Officer options only matter to the writer; the Options tab hides them unless an officer asks to see them. Member
-- options are about things officers always have, so officers don't see them.

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
		tooltip = "Show a button on the edge of the minimap: left-click opens the window, right-click its options, and drag it to move it. /pl opens the window either way." },
	{ key = "showRaidTab", member = true, kind = "checkbox", name = "Show the Raid Tab",
		tooltip = "Show the Raid tab, with every raider's role, to look at. Officers always have it." },
	{ key = "tooltipHints", kind = "checkbox", name = "Show Click Hints in Tooltips",
		tooltip = "End tooltips with the green lines saying what clicking does: on loot, rolls, the minimap button and the resize handle." },
	{ section = "Profile" },
	{ kind = "profile", name = "This Character", title = "Profile",
		tooltip = "These options are kept in a profile. Every character starts on Default, sharing its options; pick or make another profile to give this character options of its own. The menu also copies, resets and deletes profiles." },
}

-- A green line saying what clicking does, unless the player has hidden them.
function ns.AddHint(tooltip, text)
	if ns.settings.tooltipHints then GameTooltip_AddInstructionLine(tooltip, text) end
end

-- Changing an option.
function ns.SetOption(key, value)
	ns.settings[key] = value
	ns.Fire("SETTINGS_CHANGED", key)
	if ns.RefreshWindow then ns.RefreshWindow() end
end

-- Profiles are AceDB's. Switching to another, or copying into or resetting this one, changes every option at once,
-- so SETTINGS_CHANGED has no key.
function ns.ProfileChanged()
	ns.settings = ns.database.profile
	ns.Fire("SETTINGS_CHANGED")
	if ns.RefreshWindow then ns.RefreshWindow() end
end

-- The profiles there are, by name.
function ns.Profiles()
	local names = ns.database:GetProfiles()
	table.sort(names)
	return names
end

-- A new profile for this character, with the default options.
function ns.NewProfile(name)
	name = (name or ""):match("^%s*(.-)%s*$")
	if name == "" then return end
	for _, existing in ipairs(ns.Profiles()) do
		if existing == name then return ns.Print(("There's already a profile called %s."):format(name)) end
	end
	ns.database:SetProfile(name)
end

-- The dialogs behind the profile menu (UI.lua). Copying, resetting and deleting ask first, as they can't be undone.
local function Confirm(text, accept)
	return { text = text, button1 = YES, button2 = NO, OnAccept = accept, timeout = 0, whileDead = 1, hideOnEscape = 1 }
end
StaticPopupDialogs.PITIFULLOOT_NEW_PROFILE = {
	text = "Name the new profile. It starts with the default options.",
	button1 = ACCEPT, button2 = CANCEL,
	hasEditBox = 1, maxLetters = 32,
	OnShow = function(dialog) dialog:GetEditBox():SetFocus() end,
	OnAccept = function(dialog) ns.NewProfile(dialog:GetEditBox():GetText()) end,
	EditBoxOnEnterPressed = function(editBox)
		ns.NewProfile(editBox:GetText())
		editBox:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}
StaticPopupDialogs.PITIFULLOOT_COPY_PROFILE = Confirm("Copy the options from %s into %s?",
	function(_, from) ns.database:CopyProfile(from) end)
StaticPopupDialogs.PITIFULLOOT_RESET_PROFILE = Confirm("Reset every option in %s to its default?",
	function() ns.database:ResetProfile() end)
StaticPopupDialogs.PITIFULLOOT_DELETE_PROFILE = Confirm("Delete the profile %s?",
	function(_, name) ns.database:DeleteProfile(name) end)

function ns.OpenOptions()
	ns.ShowWindow("options")
end
