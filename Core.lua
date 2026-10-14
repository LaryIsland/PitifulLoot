local addonName, ns = ...

ns.warnings = {}

-- Names of things in the addon players see or click (tabs, buttons, options, commands) are marked {like this} in
-- Locales, and shown in a colour of their own: Blizzard's for links and terms in its own text. Done once every
-- locale file has loaded, so a translation's lines are marked too. Raid chat (ns.CHAT) can't carry colours.
ns.NAME_COLOR = "ff71d5ff"
for key, text in pairs(ns.L) do
	if type(text) == "string" and text:find("{", 1, true) then
		rawset(ns.L, key, (text:gsub("{(.-)}", "|c" .. ns.NAME_COLOR .. "%1|r")))
	end
end

-- The options, kept in AceDB profiles (Options.lua).
local DEFAULTS = {
	rollTime = 30,
	rerollTime = 20,
	minQuality = 4, -- epic
	announce = true, -- the writer's raid chat messages (5.3)
	whisperRefusals = true, -- the writer whispers players without the addon whose roll didn't count
	raidWarning = true, -- headlines as raid warnings, when the writer is leader or an assistant
	autoAward = false, -- the writer awards each roll as soon as it's decided
	autoRoll = 0, -- 1 rolls for you in rerolls, 2 in every roll you can take part in (ns.AUTO_ROLL)
	autoShow = true,
	autoShowLoot = true, -- open the window on the Loot tab when new loot is added
	pityByBoss = false, -- group My pity by boss inside each raid
	hideWon = false, -- leave items you've won off My pity
	hideUnrollable = false, -- leave loot you can't roll on off the Loot tab, unless you're the writer
	minimapButton = true, -- the button on the edge of the minimap (MinimapButton.lua)
	tooltipHints = true, -- the lines in tooltips saying what clicking does
	showRaidTab = false, -- a member showing the Raid tab, to look at (officers always have it)
	showOfficerOptions = false, -- the Options tab's officer options, for officers who want them
	chatLanguage = "enUS", -- the writer's raid chat and whispers (ns.CHAT_LANGUAGES), whatever the game's language
}
ns.DEFAULTS = DEFAULTS

-- Raid chat and whispers, in the language the writer picked (ns.CHAT_LANGUAGES, from Locales), which needn't be the
-- game's: a line the language hasn't translated is in English, and one English hasn't got shows as its own name, with
-- an error, as for L.
local english = ns.CHAT_LANGUAGES.enUS.text
local missingChat = {}
ns.CHAT = setmetatable({}, {
	__index = function(_, key)
		local chosen = ns.settings and ns.CHAT_LANGUAGES[ns.settings.chatLanguage]
		local text = chosen and chosen.text[key] or english[key]
		if text then return text end
		if not missingChat[key] then
			missingChat[key] = true
			geterrorhandler()("PitifulLoot: missing chat text '" .. tostring(key) .. "'")
		end
		return key
	end,
})

-- Events too frequent or uninteresting to capture; addon messages are captured decoded, in Comm.lua.
local UNCAPTURED = { CHAT_MSG_ADDON = true, GET_ITEM_INFO_RECEIVED = true }

-- Errors keep the stack they happened on, and go to the capture as well as the error handler.
local function WithStack(err)
	return tostring(err) .. (debugstack and ("\n" .. debugstack(2)) or "")
end

-- Records what happens for the test capture; does nothing unless Capture.lua (temporary) replaces it.
function ns.Capture(...) end

function ns.ReportError(where, err)
	if ns.Capture then ns.Capture("error", where, err) end
	geterrorhandler()(err)
end

local events = {}
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
	if ns.Capture and not UNCAPTURED[event] then ns.Capture("event", event, ...) end
	for _, handler in ipairs(events[event]) do
		local ok, err = xpcall(handler, WithStack, ...)
		if not ok then ns.ReportError(event, err) end
	end
end)
ns.WithStack = WithStack

-- Calls handler(...) on every `event`. Any number of modules can listen to the same event.
function ns.On(event, handler)
	if not events[event] then
		events[event] = {}
		frame:RegisterEvent(event)
	end
	table.insert(events[event], handler)
end

-- The addon's own notifications (SESSION_CHANGED, LEDGER_CHANGED and so on), mostly for the window.
local listeners = {}

function ns.Listen(name, handler)
	listeners[name] = listeners[name] or {}
	table.insert(listeners[name], handler)
end

function ns.Fire(name, ...)
	for _, handler in ipairs(listeners[name] or {}) do handler(...) end
end

function ns.Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffc69b6dPitiful Loot|r: " .. text)
end

-- Something a player should look at: a result that doesn't match what they saw, or a ledger that differs (6.3).
function ns.Warn(text)
	if ns.Capture then ns.Capture("warning", text) end
	table.insert(ns.warnings, { time = GetServerTime(), text = text })
	DEFAULT_CHAT_FRAME:AddMessage("|cffc69b6dPitiful Loot|r: |cffff4040" .. text .. "|r")
	ns.Fire("WARNINGS")
end

function ns.PlayerName()
	return (UnitName("player"))
end

-- Names can come with a realm ("Name-Realm"); comparisons ignore it.
function ns.ShortName(name)
	return name and name:match("^[^%-]+")
end

function ns.SameName(a, b)
	return a ~= nil and b ~= nil and (a == b or ns.ShortName(a) == ns.ShortName(b))
end

function ns.IsMe(name)
	return ns.SameName(name, ns.PlayerName())
end

---@class PitifulLootGlobal
---@field ledger table<string, table> each guild's ledger (Pity.lua, Ledger.lua)
---@field log table<string, table[]> each guild's full log: what this client saw, never shared (Pity.lua)
---@field names table<string, string> names by GUID, for players who aren't online
---@field classes table<string, string> class file names by GUID, to colour those names
---@field testOfficers table<string, boolean> players trusted as officers in test mode (TestCommands.lua)
---@field testMode boolean?
---@field introduced table<string, number> when each player without the addon was last whispered about it (Session.lua)
---@field perf table[]? the latest performance test runs (Perf.lua, development only)
---@field tutorialFinished boolean? every step on one of the test menu's pages has been done (TestMenu.lua)
---@field tutorialTold boolean? told, after finishing it, that /pl test opens the test menu again
---@field minimapIcon table LibDBIcon's record of the minimap button: where it sits, and whether it's hidden
---@field collapsed table<string, boolean> My pity groups the player has collapsed
---@field position table? where the window was left
---@field height number? the window's height, if the player resized it

-- Everything but the options is account-wide. The options are in profiles, which every character starts out sharing
-- (Default), and which are switched, copied and reset from the Options tab (Options.lua).
ns.On("ADDON_LOADED", function(name)
	if name ~= addonName then return end
	local db = LibStub("AceDB-3.0"):New("PitifulLootDB", {
		profile = DEFAULTS,
		global = { ledger = {}, log = {}, names = {}, classes = {}, testOfficers = {}, minimapIcon = {}, collapsed = {},
			roleOverrides = {} },
	}, true)
	ns.database = db
	ns.saved = db.global --[[@as PitifulLootGlobal]]
	ns.settings = db.profile
	for _, event in ipairs({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }) do
		db.RegisterCallback(ns, event, ns.ProfileChanged)
	end
end)

function ns.InRaidInstance()
	local _, instanceType = GetInstanceInfo()
	return instanceType == "raid"
end

-- Why test mode can't be on here, if it can't (5.5): "instance" inside a raid instance, "raidgroup" in a raid group.
-- A party is fine.
function ns.TestModeBlocked()
	if ns.InRaidInstance() then return "instance" end
	if IsInRaid() then return "raidgroup" end
end

-- Test mode (TestCommands.lua, and the test menu) keeps its own ledger, so nothing done in it reaches the guild's.
-- It's never on in a raid: it turns itself off on the way in, and this covers the moment before.
function ns.IsTestMode()
	return ns.saved ~= nil and ns.saved.testMode == true and not ns.TestModeBlocked()
end

-- Test mode keeps to this client, sending the group nothing and showing raid chat only to you, unless someone in
-- the group is trusted (/pl test trust), for testing with friends (5.5).
function ns.TestIsPrivate()
	if not ns.IsTestMode() then return false end
	local trusted = ns.saved.testOfficers
	for _, member in ipairs(ns.GroupMembers()) do
		local name = member.name and ns.ShortName(member.name)
		-- Trusted by the name typed after /pl test trust, which is a first name or a full one.
		if name and not ns.IsMe(name) and (trusted[name] or trusted[name:match("^%S+")]) then return false end
	end
	return true
end

-- Test mode can show the window as a raider without officer powers sees it; it doesn't change what the addon does.
function ns.ViewAsRaider()
	return ns.IsTestMode() and ns.saved.testViewAsRaider == true
end

-- The ledger in use is the current guild's, once the client knows which guild that is (Pity.lua).
local function UpdateGuild()
	if not ns.saved then return end
	local guild = IsInGuild() and GetGuildInfo("player") or nil
	if ns.IsTestMode() then guild = (guild or "No guild") .. " [test]" end
	if guild == ns.guild then return end
	ns.guild = guild
	ns.ledger = guild and ns.LoadLedger(guild) or nil
	if ns.ledger then ns.SignRows() end
	ns.Fire("LEDGER_READY")
	ns.Fire("LEDGER_CHANGED")
end
ns.UpdateGuild = UpdateGuild

ns.On("PLAYER_LOGIN", function()
	if IsInGuild() then C_GuildInfo.GuildRoster() end
	UpdateGuild()
end)
ns.On("PLAYER_GUILD_UPDATE", UpdateGuild)
ns.On("GUILD_ROSTER_UPDATE", UpdateGuild)
