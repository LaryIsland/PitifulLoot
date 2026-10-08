local addonName, ns = ...

ns.ledgers = {}
ns.warnings = {}

local DEFAULTS = {
	officerRank = 1, -- guild ranks from 0 (guild master) to this one count as officers (open question 6)
	rollTime = 30,
	rerollTime = 20,
	minQuality = 4, -- epic
	announce = true,
	autoShow = true,
}

local events = {}
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
	for _, handler in ipairs(events[event]) do
		local ok, err = pcall(handler, ...)
		if not ok then geterrorhandler()(err) end
	end
end)

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

-- Ledgers and names are account-wide; settings are per profile.
ns.On("ADDON_LOADED", function(name)
	if name ~= addonName then return end
	local db = LibStub("AceDB-3.0"):New("PitifulLootDB", { global = { ledgers = {}, names = {} }, profile = DEFAULTS }, true)
	local function UseProfile() ns.settings = db.profile end
	db.RegisterCallback(ns, "OnProfileChanged", UseProfile)
	db.RegisterCallback(ns, "OnProfileCopied", UseProfile)
	db.RegisterCallback(ns, "OnProfileReset", UseProfile)
	ns.database = db
	ns.db = db.global
	UseProfile()
end)

-- A guild's ledger, replayed from its saved entries. If a saved entry won't replay, the saved copy is left alone so
-- nothing is lost, and the ledger stops before that entry with loadError set.
function ns.GetLedger(guild)
	if not ns.ledgers[guild] then
		local ledger, bad, err = ns.LoadLedger(ns.db.ledgers[guild])
		if err then
			ledger.loadError = string.format("entry %d: %s", bad, err)
		else
			ns.db.ledgers[guild] = ledger.entries
		end
		ns.ledgers[guild] = ledger
	end
	return ns.ledgers[guild]
end

-- Swaps in a ledger fetched from an officer with /pl resync.
function ns.ReplaceLedger(ledger)
	ns.db.ledgers[ns.guild] = ledger.entries
	ns.ledgers[ns.guild] = ledger
	ns.ledger = ledger
	ns.Fire("LEDGER_CHANGED")
end

-- The ledger in use is the current guild's, once the client knows which guild that is.
local function UpdateGuild()
	if not ns.db then return end
	local guild = IsInGuild() and GetGuildInfo("player") or nil
	if guild == ns.guild then return end
	ns.guild = guild
	ns.ledger = guild and ns.GetLedger(guild) or nil
	if ns.ledger and ns.ledger.loadError then
		ns.Warn("Your saved ledger couldn't be fully loaded (" .. ns.ledger.loadError .. "). /pl resync <officer> fetches theirs.")
	end
	ns.Fire("LEDGER_READY")
	ns.Fire("LEDGER_CHANGED")
end

ns.On("PLAYER_LOGIN", function()
	if IsInGuild() then C_GuildInfo.GuildRoster() end
	UpdateGuild()
end)
ns.On("PLAYER_GUILD_UPDATE", UpdateGuild)
ns.On("GUILD_ROSTER_UPDATE", UpdateGuild)
