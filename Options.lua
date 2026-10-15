local _, ns = ...
local L = ns.L

-- The options, shown on the window's Options tab (UI.lua). They're account-wide, the same for every character.
-- Officer options only matter to the writer; the Options tab hides them unless an officer asks to see them. Member
-- options are about things officers always have, so officers don't see them.

local function Seconds(value)
	return L.OPT_SECONDS:format(value)
end

-- What auto-roll does: nothing, roll for you in rerolls only, or in every roll you can take part in.
ns.AUTO_ROLL = { OFF = 0, REROLLS = 1, ALL = 2 }
-- What the writer's client does by itself once a roll is decided: nothing, award it if it has winners, or also take the
-- next step for one no one rolled on (Disenchant, Keep to sell, or a BoE's greed roll), as the writer's button would.
ns.AUTO_FINISH = { OFF = 0, AWARDS = 1, ALL = 2 }

-- The raid chat languages there are, by name.
local chatLanguages = {}
for code, language in pairs(ns.CHAT_LANGUAGES) do chatLanguages[#chatLanguages + 1] = { code, language.name } end
table.sort(chatLanguages, function(a, b) return a[2] < b[2] end)

-- The fonts the addon's text can be in (Fonts.lua).
local fonts = {}
for i, font in ipairs(ns.FONTS) do fonts[i] = { font[1], font[2] } end

ns.OPTIONS = {
	{ section = L.OPT_SECTION_ANNOUNCEMENTS, officer = true },
	{ key = "chatLanguage", officer = true, kind = "dropdown", name = L.OPT_CHAT_LANGUAGE, choices = chatLanguages,
		tooltip = L.OPT_CHAT_LANGUAGE_TIP },
	{ key = "announce", officer = true, kind = "checkbox", name = L.OPT_ANNOUNCE, tooltip = L.OPT_ANNOUNCE_TIP },
	{ key = "whisperRefusals", officer = true, kind = "checkbox", name = L.OPT_WHISPER_REFUSALS, tooltip = L.OPT_WHISPER_REFUSALS_TIP },
	{ key = "raidWarning", officer = true, kind = "checkbox", name = L.OPT_RAID_WARNING, tooltip = L.OPT_RAID_WARNING_TIP },
	{ section = L.OPT_SECTION_RUNNING_ROLLS, officer = true },
	{ key = "rollTime", officer = true, kind = "slider", name = L.OPT_ROLL_TIME, min = 10, max = 120, step = 5, format = Seconds,
		tooltip = L.OPT_ROLL_TIME_TIP },
	{ key = "rerollTime", officer = true, kind = "slider", name = L.OPT_REROLL_TIME, min = 10, max = 60, step = 5, format = Seconds,
		tooltip = L.OPT_REROLL_TIME_TIP },
	{ key = "minQuality", officer = true, kind = "dropdown", name = L.OPT_LOOT_QUALITY,
		choices = { { 2, L.OPT_QUALITY_UNCOMMON }, { 3, L.OPT_QUALITY_RARE }, { 4, L.OPT_QUALITY_EPIC }, { 5, L.OPT_QUALITY_LEGENDARY } },
		tooltip = L.OPT_LOOT_QUALITY_TIP },
	{ key = "autoFinish", officer = true, kind = "dropdown", name = L.OPT_AUTO_AWARD,
		choices = {
			{ ns.AUTO_FINISH.OFF, L.OPT_AUTO_AWARD_OFF }, { ns.AUTO_FINISH.AWARDS, L.OPT_AUTO_AWARD_AWARDS },
			{ ns.AUTO_FINISH.ALL, L.OPT_AUTO_AWARD_ALL },
		},
		tooltip = L.OPT_AUTO_AWARD_TIP },
	{ section = L.OPT_SECTION_ROLLING },
	{ key = "autoRoll", kind = "dropdown", name = L.OPT_AUTO_ROLL,
		choices = {
			{ ns.AUTO_ROLL.OFF, L.OPT_AUTO_ROLL_OFF }, { ns.AUTO_ROLL.REROLLS, L.OPT_AUTO_ROLL_REROLLS },
			{ ns.AUTO_ROLL.ALL, L.OPT_AUTO_ROLL_ALL },
		},
		tooltip = L.OPT_AUTO_ROLL_TIP },
	{ section = L.OPT_SECTION_WINDOW },
	{ key = "font", kind = "dropdown", name = L.OPT_FONT, choices = fonts, tooltip = L.OPT_FONT_TIP },
	{ key = "autoShow", kind = "checkbox", name = L.OPT_AUTO_SHOW, tooltip = L.OPT_AUTO_SHOW_TIP },
	{ key = "autoShowLoot", kind = "checkbox", name = L.OPT_AUTO_SHOW_LOOT, tooltip = L.OPT_AUTO_SHOW_LOOT_TIP },
	{ key = "hideUnrollable", kind = "checkbox", name = L.OPT_HIDE_UNROLLABLE, tooltip = L.OPT_HIDE_UNROLLABLE_TIP },
	{ key = "pityByBoss", kind = "checkbox", name = L.OPT_PITY_BY_BOSS, tooltip = L.OPT_PITY_BY_BOSS_TIP },
	{ key = "hideWon", kind = "checkbox", name = L.OPT_HIDE_WON, tooltip = L.OPT_HIDE_WON_TIP },
	{ key = "minimapButton", kind = "checkbox", name = L.OPT_MINIMAP_BUTTON, tooltip = L.OPT_MINIMAP_BUTTON_TIP },
	{ key = "showRaidTab", member = true, kind = "checkbox", name = L.OPT_SHOW_RAID_TAB, tooltip = L.OPT_SHOW_RAID_TAB_TIP },
	{ key = "tooltipHints", kind = "checkbox", name = L.OPT_TOOLTIP_HINTS, tooltip = L.OPT_TOOLTIP_HINTS_TIP },
	{ section = L.OPT_SECTION_PROFILE },
	{ kind = "profile", name = L.OPT_PROFILE, title = L.OPT_PROFILE_TITLE, tooltip = L.OPT_PROFILE_TIP },
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
		if existing == name then return ns.Print(L.PROFILE_EXISTS:format(name)) end
	end
	ns.database:SetProfile(name)
end

-- The dialogs behind the profile menu (UI.lua). Copying, resetting and deleting ask first, as they can't be undone.
local function Confirm(text, accept)
	return { text = text, button1 = YES, button2 = NO, OnAccept = accept, timeout = 0, whileDead = 1, hideOnEscape = 1 }
end
StaticPopupDialogs.PITIFULLOOT_NEW_PROFILE = {
	text = L.PROFILE_NEW_DIALOG,
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
StaticPopupDialogs.PITIFULLOOT_COPY_PROFILE = Confirm(L.PROFILE_COPY_DIALOG,
	function(_, from) ns.database:CopyProfile(from) end)
StaticPopupDialogs.PITIFULLOOT_RESET_PROFILE = Confirm(L.PROFILE_RESET_DIALOG,
	function() ns.database:ResetProfile() end)
StaticPopupDialogs.PITIFULLOOT_DELETE_PROFILE = Confirm(L.PROFILE_DELETE_DIALOG,
	function(_, name) ns.database:DeleteProfile(name) end)

function ns.OpenOptions()
	ns.ShowWindow("options")
end
