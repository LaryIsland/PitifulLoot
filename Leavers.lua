local _, ns = ...

-- Players leaving and rejoining the guild, which starts and stops their pity decay (4.9), recorded automatically.
-- Officers' clients compare the guild roster with the ledger. The online officer with the highest rank (then first by
-- name) records each change; the others wait longer, in that order, and only step in if it still hasn't been
-- recorded, so an officer without the addon can't stop it happening.

local FIRST_DELAY = 10
local STEP_DELAY = 20
local SETTLE = 60 -- seconds after the ledger loads before the roster is trusted to be complete
local CHECK_INTERVAL = 60

local scheduled = {}
local readyAt

local function Tracked(state)
	local ids = {}
	for _, store in ipairs({ state.pity, state.greed }) do
		for id in pairs(store) do ids[id] = true end
	end
	for id in pairs(state.left) do ids[id] = true end
	return ids
end

-- "leave" or "rejoin" if the ledger and the roster disagree about a player, otherwise nil.
local function Change(id)
	local inGuild = ns.GuildMember(id) ~= nil
	local left = ns.ledger.state.left[id] ~= nil
	if left and inGuild then return "rejoin" end
	if not left and not inGuild then return "leave" end
end

local function MyTurn()
	for i, officer in ipairs(ns.OnlineOfficers()) do
		if ns.IsMe(officer.name) then return i - 1 end
	end
end

local function Record(id, kind, noticed)
	scheduled[id] = nil
	if not ns.ledger or Change(id) ~= kind then return end
	local ok = ns.AppendEntry({ type = kind, id = id, time = noticed, by = ns.PlayerName() })
	if ok then
		local text = kind == "leave" and ns.L.MSG_LEFT_GUILD or ns.L.MSG_REJOINED_GUILD
		ns.Print(text:format(ns.NameOf(id), (ns.ledger:Revision())))
	end
end

local function Check()
	-- A test ledger's made-up players are never in the guild.
	if ns.IsTestMode() or not ns.ledger or not readyAt or GetTime() < readyAt or GetNumGuildMembers() == 0 then return end
	local turn = MyTurn()
	if not turn then return end
	for id in pairs(Tracked(ns.ledger.state)) do
		local kind = Change(id)
		if kind and not scheduled[id] then
			scheduled[id] = true
			local noticed = GetServerTime()
			C_Timer.After(FIRST_DELAY + STEP_DELAY * turn, function() Record(id, kind, noticed) end)
		end
	end
end

local ticker
ns.Listen("LEDGER_READY", function()
	scheduled = {}
	readyAt = ns.ledger and GetTime() + SETTLE or nil
	if ns.ledger and not ticker then
		ticker = C_Timer.NewTicker(CHECK_INTERVAL, function()
			if ns.IsOfficer(ns.PlayerName()) then C_GuildInfo.GuildRoster() end
			Check()
		end)
	end
end)
ns.On("GUILD_ROSTER_UPDATE", Check)
