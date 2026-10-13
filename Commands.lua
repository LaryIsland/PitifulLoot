local _, ns = ...
local L = ns.L

local HELP = {
	L.HELP_TOGGLE, L.HELP_OPTIONS, L.HELP_WRITER, L.HELP_ROLL, L.HELP_ROUND, L.HELP_DISENCHANT, L.HELP_SELL, L.HELP_PASS,
	L.HELP_OS, L.HELP_PITY, L.HELP_LEAVE, L.HELP_ADJUST, L.HELP_RESYNC, L.HELP_STATUS,
	"/pl test - commands for trying the addon out in game (temporary)",
}

-- Splits arguments, keeping an item link (which has spaces in its name) as one.
local function Args(text)
	local args = {}
	local rest = text
	while rest ~= "" do
		rest = rest:gsub("^%s+", "")
		local link = rest:match("^(|c.-|h|r)")
		local word = link or rest:match("^(%S+)")
		if not word then break end
		args[#args + 1] = word
		rest = rest:sub(#word + 1)
	end
	return args
end

local function Officer()
	if ns.IsOfficer(ns.PlayerName()) then return true end
	ns.Print(L.MSG_OFFICERS_ONLY)
end

local function Player(name)
	local guid = name and ns.FindPlayer(name)
	if not guid then ns.Print(L.MSG_PLAYER_NOT_FOUND:format(tostring(name))) end
	return guid
end

local function Record(entry)
	entry.time, entry.by = GetServerTime(), ns.PlayerName()
	local ok, err = ns.AppendEntry(entry)
	ns.Print(ok and L.MSG_RECORDED:format(entry.rev) or L.MSG_NOT_RECORDED:format(err))
end

local function ShowPity(name)
	local guid = name and Player(name) or UnitGUID("player")
	if not guid or not ns.ledger then return end
	local state = ns.ledger.state
	local lines = {}
	for item in pairs(state.pity[guid] or {}) do
		lines[#lines + 1] = ("%s +%d"):format(ns.ItemLink(item), state:GetPity(guid, item, false, GetServerTime()))
	end
	for item in pairs(state.greed[guid] or {}) do
		lines[#lines + 1] = L.MSG_PITY_GREED:format(ns.ItemLink(item), state:GetPity(guid, item, true, GetServerTime()))
	end
	for item in pairs(state.won[guid] or {}) do lines[#lines + 1] = L.MSG_PITY_WON:format(ns.ItemLink(item)) end
	ns.Print(lines[1] and ns.NameOf(guid) .. ":" or L.MSG_PITY_NONE:format(ns.NameOf(guid)))
	for _, line in ipairs(lines) do ns.Print("  " .. line) end
end

local commands = {}
ns.commands = commands -- TestCommands.lua adds /pl test

function commands.writer() ns.ClaimWriter() end
function commands.close() ns.CloseRound() end
function commands.cancel() ns.CancelRoll() end
function commands.award() ns.Award() end
function commands.disenchant() ns.Disenchant() end
function commands.sell() ns.KeepToSell() end
function commands.pass() ns.Pass() end
function commands.pity(args) ShowPity(args[2]) end
function commands.resync(args) ns.Resync(args[2]) end
function commands.help() for _, line in ipairs(HELP) do ns.Print(line) end end
function commands.options() ns.OpenOptions() end

function commands.roll(args)
	local item = ns.ItemID(args[2])
	if not item then return ns.Print(L.USAGE_ROLL) end
	ns.StartRoll(item, tonumber(args[3]) or 1, args[3] == "greed" or args[4] == "greed")
end

function commands.os(args)
	local guid = Player(args[2])
	if guid then ns.ToggleOffSpec(guid) end
end

function commands.leave(args)
	local guid = Officer() and Player(args[2])
	if guid then Record({ type = "leave", id = guid }) end
end

function commands.rejoin(args)
	local guid = Officer() and Player(args[2])
	if guid then Record({ type = "rejoin", id = guid }) end
end

function commands.adjust(args)
	local guid = Officer() and Player(args[2])
	local item, pity = ns.ItemID(args[3]), tonumber(args[4])
	if not guid then return end
	if not item or not pity then return ns.Print(L.USAGE_ADJUST) end
	Record({ type = "adjust", id = guid, item = item, pity = pity, unlock = args[5] == "unlock" or nil })
end

function commands.status()
	if ns.ledger then
		local rev, head = ns.ledger:Revision()
		ns.Print((ns.SyncBusy() and L.MSG_STATUS_SYNCING or L.MSG_STATUS):format(ns.guild, rev, head:sub(1, 8)))
	else
		ns.Print(L.MSG_STATUS_NO_LEDGER)
	end
	ns.Print(ns.live.writer and L.WRITER:format(ns.live.writer) or L.WRITER_NONE)
	for i = math.max(#ns.warnings - 4, 1), #ns.warnings do ns.Print("|cffff4040" .. ns.warnings[i].text .. "|r") end
end

SLASH_PITIFULLOOT1 = "/pl"
SLASH_PITIFULLOOT2 = "/pitifulloot"
SlashCmdList.PITIFULLOOT = function(text)
	ns.Capture("command", text)
	local args = Args(text or "")
	local command = args[1] and commands[args[1]:lower()]
	if command then
		command(args)
	elseif args[1] then
		commands.help()
	else
		ns.ToggleWindow()
	end
end
