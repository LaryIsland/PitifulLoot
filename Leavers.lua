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

-- Everyone with pity in the table (someone with only wins has nothing to decay), and every leaver.
local function Tracked(data)
	local ids = {}
	for id, subs in pairs(data.rows) do
		for _, sub in pairs(subs) do
			for _, cell in pairs(sub.cells) do
				if cell ~= ns.CELL_WON then ids[id] = true end
			end
		end
	end
	for id in pairs(data.leavers) do ids[id] = true end
	return ids
end

-- "leave" or "rejoin" if the table and the roster disagree about a player, otherwise nil.
local function Change(id)
	local inGuild = ns.GuildMember(id) ~= nil
	local left = ns.ledger.data.leavers[id] ~= nil
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
	if not ns.ledger or not ns.HoldsTable() or Change(id) ~= kind then return end
	-- A leave is dated when it was first seen; a rejoin, now.
	local ok = ns.RecordChange(ns.NewChange({ op = kind, id = id, time = kind == "leave" and noticed or nil }))
	if ok then
		local text = kind == "leave" and ns.L.MSG_LEFT_GUILD or ns.L.MSG_REJOINED_GUILD
		ns.Print(text:format(ns.NameOf(id), ns.Head().rev))
	end
end

local function Check()
	-- A test ledger's made-up players are never in the guild.
	if ns.IsTestMode() or not ns.ledger or not ns.HoldsTable() or not readyAt or GetTime() < readyAt
		or GetNumGuildMembers() == 0 then return end
	local turn = MyTurn()
	if not turn then return end
	for id in pairs(Tracked(ns.ledger.data)) do
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
