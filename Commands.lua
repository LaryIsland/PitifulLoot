local _, ns = ...

local HELP = {
	"/pl - show or hide the window",
	"/pl writer - run loot rolls for this group (officers)",
	"/pl roll <item> [copies] [greed] - start a roll",
	"/pl close | cancel | award - end the current round, drop the roll, or record and hand out the item",
	"/pl os <name> - flip a roll's off-spec flag before the first round closes",
	"/pl pity [name] - list pity",
	"/pl leave <name> | rejoin <name> - record a player leaving or rejoining the guild (officers)",
	"/pl adjust <name> <item> <pity> [unlock] - correct pity, or lift a lockout (officers)",
	"/pl resync <officer> - replace your ledger with an officer's",
	"/pl status - ledger revision, writer and warnings",
	"/pl officerrank <n> - the lowest guild rank that counts as an officer (0 is the guild master)",
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
	ns.Print("Only officers can do that.")
end

local function Player(name)
	local guid = name and ns.FindPlayer(name)
	if not guid then ns.Print("Can't find " .. tostring(name) .. " in your group or guild.") end
	return guid
end

local function Record(entry)
	entry.time, entry.by = GetServerTime(), ns.PlayerName()
	local ok, err = ns.AppendEntry(entry)
	ns.Print(ok and ("Recorded as revision %d."):format(entry.rev) or ("Not recorded: %s."):format(err))
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
		lines[#lines + 1] = ("%s +%d (greed)"):format(ns.ItemLink(item), state:GetPity(guid, item, true, GetServerTime()))
	end
	for item in pairs(state.won[guid] or {}) do lines[#lines + 1] = ns.ItemLink(item) .. " won" end
	ns.Print(ns.NameOf(guid) .. (lines[1] and ":" or " has no pity yet."))
	for _, line in ipairs(lines) do ns.Print("  " .. line) end
end

local commands = {}

function commands.writer() ns.ClaimWriter() end
function commands.close() ns.CloseRound() end
function commands.cancel() ns.CancelRoll() end
function commands.award() ns.Award() end
function commands.pity(args) ShowPity(args[2]) end
function commands.resync(args) ns.Resync(args[2]) end
function commands.help() for _, line in ipairs(HELP) do ns.Print(line) end end

function commands.roll(args)
	local item = ns.ItemID(args[2])
	if not item then return ns.Print("/pl roll <item link or ID> [copies] [greed]") end
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
	if not item or not pity then return ns.Print("/pl adjust <name> <item> <pity> [unlock]") end
	Record({ type = "adjust", id = guid, item = item, pity = pity, unlock = args[5] == "unlock" or nil })
end

function commands.officerrank(args)
	local rank = tonumber(args[2])
	if rank then ns.settings.officerRank = rank end
	ns.Print(("Guild ranks 0 to %d count as officers."):format(ns.settings.officerRank))
end

function commands.status()
	if ns.ledger then
		local rev, head = ns.ledger:Revision()
		ns.Print(("%s ledger: revision %d (%s)%s."):format(ns.guild, rev, head:sub(1, 8), ns.SyncBusy() and ", syncing" or ""))
	else
		ns.Print("No guild ledger loaded.")
	end
	ns.Print("Writer: " .. (ns.live.writer or "none"))
	for i = math.max(#ns.warnings - 4, 1), #ns.warnings do ns.Print("|cffff4040" .. ns.warnings[i].text .. "|r") end
end

SLASH_PITIFULLOOT1 = "/pl"
SLASH_PITIFULLOOT2 = "/pitifulloot"
SlashCmdList.PITIFULLOOT = function(text)
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
