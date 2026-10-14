local _, ns = ...
local L = ns.L

local HELP = {
	L.HELP_TOGGLE, L.HELP_OPTIONS, L.HELP_WRITER, L.HELP_ROLL, L.HELP_ROUND, L.HELP_DISENCHANT, L.HELP_SELL, L.HELP_PASS,
	L.HELP_OS, L.HELP_PITY, L.HELP_LEAVE, L.HELP_ADJUST, L.HELP_RESYNC, L.HELP_STATUS, L.HELP_LOG, L.HELP_TEST,
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

-- An officer's change to the ledger (6.4).
local function Record(change)
	local ok, err = ns.RecordChange(ns.NewChange(change))
	ns.Print(ok and L.MSG_RECORDED:format(ns.Head().rev) or L.MSG_NOT_RECORDED:format(err))
end

-- A player's pity and wins, from their sub-rows (raid -> sub-row), with leaver decay where this client knows of it.
function ns.ShowPityOf(name, rows, guid)
	local lines = {}
	for _, sub in pairs(rows) do
		for item, cell in pairs(sub.cells) do
			if cell == ns.CELL_WON then
				lines[#lines + 1] = L.MSG_PITY_WON:format(ns.ItemLink(item))
			else
				local pity = guid and ns.PityOf(guid, item) or (cell + 1) * 10
				if pity > 0 then lines[#lines + 1] = ("%s +%d"):format(ns.ItemLink(item), pity) end
			end
		end
	end
	table.sort(lines)
	ns.Print(lines[1] and name .. ":" or L.MSG_PITY_NONE:format(name))
	for _, line in ipairs(lines) do ns.Print("  " .. line) end
end

-- Your own pity; anyone's for an officer, who holds the table; or else asked of that player's own addon (6.3).
local function ShowPity(name)
	local guid = name and Player(name) or UnitGUID("player")
	if not guid or not ns.ledger then return end
	if guid == UnitGUID("player") or ns.HoldsTable() then return ns.ShowPityOf(ns.NameOf(guid), ns.LiveRows(guid), guid) end
	local member = ns.GroupMember(guid) or ns.GuildMember(guid)
	if member and member.name then ns.AskPity(member.name) end
end

-- The full log (6.1) ----------------------------------------------------------------------------------------------

local function Name(guid)
	return ns.NameOf(guid) or ns.LoggedName(guid) or "?"
end

local function Names(list)
	local names = {}
	for i, guid in ipairs(list or {}) do names[i] = Name(guid) end
	table.sort(names)
	return names[1] and table.concat(names, ", ") or L.LOG_NOBODY
end

local function CellText(cell)
	if cell == ns.CELL_WON then return L.PITY_WON end
	return ("+%d"):format(cell and (cell + 1) * ns.PITY_STEP or 0)
end

local ROLE_BY_CODE = {}
for role, code in pairs(ns.ROLE_CODES) do ROLE_BY_CODE[code] = role end

-- A line for one event in the log.
local function Describe(e)
	local c = e.kind == "change" and type(e.change) == "table" and e.change
	if e.kind == "award" then
		local won, losers = {}, {}
		for _, id in ipairs(e.winners or {}) do won[id] = true end
		for id in pairs(e.entrants or {}) do
			if not won[id] then losers[#losers + 1] = id end
		end
		if e.greed then return L.LOG_GREED:format(ns.ItemLink(e.item), Names(e.winners), e.writer or "?") end
		return L.LOG_ROLL:format(ns.ItemLink(e.item), Names(e.winners), Names(losers), e.writer or "?")
	elseif c and c.op == "result" then
		return L.LOG_RESULT:format(ns.ItemLink(c.item), Names(c.winners), Names(c.losers), Name(c.by))
	elseif c and c.op == "adjust" and c.won then
		return L.LOG_WON:format(Name(c.id), ns.ItemLink(c.item), Name(c.by))
	elseif c and c.op == "adjust" then
		local amount = ("%+d"):format((c.steps or 0) * ns.PITY_STEP)
		return (c.unlock and L.LOG_UNLOCK or L.LOG_ADJUST):format(Name(c.id), ns.ItemLink(c.item), amount, Name(c.by))
	elseif c and (c.op == "leave" or c.op == "rejoin") then
		return (c.op == "leave" and L.LOG_LEAVE or L.LOG_REJOIN):format(Name(c.id), Name(c.by))
	elseif c and c.op == "itemroles" then
		return L.LOG_ITEMROLES:format(ns.ItemLink(c.item), Name(c.by))
	elseif c and c.op == "role" then
		local role = ROLE_BY_CODE[c.role]
		return L.LOG_ROLE:format(Name(c.id), role and ns.ROLE_NAMES[role] or L.LOG_ROLE_UNKNOWN, Name(c.by))
	elseif e.kind == "merge" then
		return L.LOG_MERGE:format(Name(e.by), e.changes or 0, e.rev or 0)
	elseif e.kind == "base" then
		return L.LOG_BASE:format(e.from or "?", e.rev or 0)
	elseif e.kind == "row" then
		local items = {}
		for item, cell in pairs(e.cells or {}) do items[#items + 1] = ns.ItemLink(item) .. " " .. CellText(cell) end
		table.sort(items)
		return L.LOG_ROW:format(e.officer or "?", table.concat(items, ", "))
	elseif e.kind == "wonbefore" then
		return L.LOG_WONBEFORE:format(table.concat(e.reporters or {}, ", "), Name(e.id), ns.ItemLink(e.item))
	elseif e.kind == "doublewin" then
		return L.LOG_DOUBLEWIN:format(Name(e.id), ns.ItemLink(e.item))
	end
	return tostring(e.kind)
end

local function When(time)
	return date("%d %b %H:%M", tonumber(time) or 0)
end

-- /pl log [count]: the latest events in the full log, then the ledger checked against it.
local function ShowLog(count)
	local events = ns.LogEvents()
	if not events[1] then return ns.Print(L.LOG_EMPTY) end
	count = math.min(count or 10, #events)
	ns.Print(L.LOG_HEADER:format(count, #events))
	for i = #events - count + 1, #events do ns.Print("  " .. When(events[i].time) .. "  " .. Describe(events[i])) end
	ns.ReportLogCheck()
end

-- The ledger checked against the log, in chat. After a resync (`officer`, whose table was taken), it checks from
-- before it, to show what the old table had that the new one doesn't.
function ns.ReportLogCheck(officer)
	local checked, mismatches, since = ns.CheckLog(officer ~= nil)
	if officer then ns.Print(L.LOG_CHECK_RESYNC:format(officer)) end
	if since then ns.Print(L.LOG_CHECK_SINCE:format(When(since))) end
	if checked == 0 then return ns.Print(L.LOG_CHECK_NONE) end
	if not mismatches[1] then return ns.Print(L.LOG_CHECK_OK:format(checked)) end
	for _, m in ipairs(mismatches) do
		ns.Warn(L.LOG_CHECK_BAD:format(Name(m[1]), ns.ItemLink(m[2]), CellText(m[3]), CellText(m[4]), When(m[5])))
	end
	ns.Print(officer and L.LOG_CHECK_RESYNC_HINT or L.LOG_CHECK_HINT)
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
function commands.log(args) ShowLog(tonumber(args[2])) end
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
	if guid then Record({ op = "leave", id = guid }) end
end

function commands.rejoin(args)
	local guid = Officer() and Player(args[2])
	if guid then Record({ op = "rejoin", id = guid }) end
end

-- An adjustment adds or takes away pity rather than setting it, so officers' changes made apart all count (6.4).
-- `unlock` lifts a win, on its own or before the change; `won` records one.
function commands.adjust(args)
	local guid = Officer() and Player(args[2])
	local item = ns.ItemID(args[3])
	if guid and item and args[4] == "won" then
		if ns.HasWon(guid, item) then return ns.Print(L.MSG_ADJUST_ALREADY_WON:format(ns.NameOf(guid), ns.ItemLink(item))) end
		return Record({ op = "adjust", id = guid, item = item, steps = 0, won = true })
	end
	local unlock = args[4] == "unlock" or args[5] == "unlock"
	local change = args[4] == "unlock" and 0 or tonumber(args[4])
	if not guid then return end
	if not item or not change then return ns.Print(L.USAGE_ADJUST) end
	-- Pity only ever goes in steps of 10 (4.1), and a win is only lifted on purpose.
	if change % ns.PITY_STEP ~= 0 or math.abs(change) > ns.PITY_MAX or (change == 0 and not unlock) then
		return ns.Print(L.MSG_PITY_STEPS)
	end
	if ns.HasWon(guid, item) and not unlock then
		return ns.Print(L.MSG_ADJUST_WON:format(ns.NameOf(guid), ns.ItemLink(item)))
	end
	Record({ op = "adjust", id = guid, item = item, steps = change / ns.PITY_STEP, unlock = unlock or nil })
end

function commands.status()
	if ns.ledger then
		local head = ns.Head()
		ns.Print((ns.SyncBusy() and L.MSG_STATUS_SYNCING or L.MSG_STATUS):format(ns.guild, head.rev, ns.ToHex(ns.ledger:Hash()):sub(1, 8)))
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
