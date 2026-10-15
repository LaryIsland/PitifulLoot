local _, ns = ...
local L = ns.L

-- Each raider's role (tank, healer or damage) for off-spec rolls (4.6), where it came from, and an officer's say on
-- it from the Raid tab.

-- The roles each class can fill. A class with one role is always that role; a role its class can't fill is ignored.
local CLASS_ROLES = {
	WARRIOR = { TANK = true, DAMAGER = true },
	PRIEST = { HEALER = true, DAMAGER = true },
	PALADIN = { TANK = true, HEALER = true, DAMAGER = true },
	SHAMAN = { TANK = true, HEALER = true, DAMAGER = true },
	DRUID = { TANK = true, HEALER = true, DAMAGER = true },
	MAGE = { DAMAGER = true }, WARLOCK = { DAMAGER = true }, ROGUE = { DAMAGER = true }, HUNTER = { DAMAGER = true },
}
ns.CLASS_ROLES = CLASS_ROLES

-- The role each class's capstone means (the level 40 talent, its tree's last node), by the tree's place in the talent
-- window. Only one capstone can be known at a time. The capstone is found by its place, at the foot of its tree, never
-- by name, as names are in the client's own language. Berserk druids and Rage of the Farseer shamans may tank or do
-- damage, so their capstone narrows it to those two, and their gear says which (GearRole), or an officer does. A
-- capstone that settles a role on its own is final, whatever the gear.
local TANK_OR_DAMAGE = { TANK = true, DAMAGER = true }
local CAPSTONES = {
	DRUID = { "DAMAGER", TANK_OR_DAMAGE, "HEALER" }, -- Moonkin Form, Berserk, Wild Growth
	PALADIN = { "HEALER", "TANK", "DAMAGER" }, -- Light's Vigil, Holy Shield, Twist of Light
	PRIEST = { "HEALER", "HEALER", "DAMAGER" }, -- Power Infusion, Prayer of Mending, Shadowform
	SHAMAN = { "DAMAGER", TANK_OR_DAMAGE, "HEALER" }, -- Lava Burst, Rage of the Farseer, Riptide
	WARRIOR = { "DAMAGER", "DAMAGER", "TANK" }, -- Mortal Strike, Bloodthirst, Shield Slam
}
-- The roles a class's ambiguous capstone leaves open, if it has one.
local AMBIGUOUS = {}
for class, capstones in pairs(CAPSTONES) do
	for _, role in ipairs(capstones) do
		if type(role) == "table" then AMBIGUOUS[class] = role end
	end
end
-- The role a raider is taken to have while theirs is unknown: priests heal and the rest do damage, except that a
-- warrior whose talents could be read but don't reveal their spec tanks.
local FALLBACK = { PRIEST = "HEALER" }
local NO_SPEC_FALLBACK = { WARRIOR = "TANK" }
function ns.FallbackRole(class, reason)
	return reason == "nocapstone" and NO_SPEC_FALLBACK[class] or FALLBACK[class] or "DAMAGER"
end

-- Where a role came from, with what the Raid tab's tooltips say about it. A role that's certain (from talents, or a
-- class with one role) says nothing; one worked out from talents and gear together says so, as it isn't.
ns.ROLE_SOURCES = {
	officer = L.ROLE_SOURCE_OFFICER,
	raid = L.ROLE_SOURCE_RAID,
	known = L.ROLE_SOURCE_KNOWN, -- their last known role, as their talents are ambiguous
	gear = L.ROLE_SOURCE_GEAR, -- their talents are ambiguous, and their gear says which
	talents = false, -- told by their own client
	inspect = false, -- read by inspecting them
}

-- What went wrong the last time a raider's talents were looked at, for the Raid tab: why their role is unknown, or
-- why an inspect an officer asked for didn't find it.
ns.UNKNOWN_REASONS = {
	far = L.REASON_FAR,
	noreply = L.REASON_NOREPLY,
	unreadable = L.REASON_UNREADABLE,
	ambiguous = L.REASON_AMBIGUOUS,
	nocapstone = L.REASON_NOCAPSTONE,
}
-- The reasons that are about the talents themselves, which inspecting again won't change: they ask an officer to set
-- the role, so they're done with once one has.
local SETTLED = { ambiguous = true, nocapstone = true }
ns.SETTLED_REASONS = SETTLED

-- A reason, on one line for chat.
local function ReasonText(reason)
	return (ns.UNKNOWN_REASONS[reason]:gsub("\n", " "))
end

-- Talents -----------------------------------------------------------------------------------------------------------

-- The talent config the game keeps for the player last inspected.
local INSPECT_CONFIG = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID or -1

local function EntryName(configID, entryID)
	local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
	local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
	local name = definition and (definition.overrideName or (definition.spellID and C_Spell.GetSpellName(definition.spellID)))
	if canaccessvalue(name) then return name end
end

-- A talent config's talents: `read`, how many nodes could be read; `trees`, each talent tree in order with whether
-- its last node is taken, if the trees can be told apart; and with `names` (for the probe), `taken`, the names of the
-- talents taken, as a set, and each tree's `capstone` by name. Looking names up is most of the garbage a read leaves
-- (/pl perf), and roles go by place, never by name, so they're only looked up for the probe. Nil if nothing could be
-- read. Forever's talents are trait trees, its three talent trees being
-- groups in one, so they're read node by node as its own talent window does. The player's own config is their
-- active spec's (C_ClassTalents.GetActiveConfigID); INSPECT_CONFIG is an inspected player's.
local function ReadTalents(configID, names)
	local config = configID and C_Traits.GetConfigInfo(configID)
	local treeID = config and config.treeIDs and config.treeIDs[1]
	if not treeID then return nil end
	local trees, treeOf = {}, {}
	local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}
	table.sort(groups, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
	for index, group in ipairs(groups) do
		trees[index] = { name = group.displayName }
		treeOf[group.groupID] = index
	end
	local talents = { taken = {}, read = 0 }
	for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
		local node = C_Traits.GetNodeInfo(configID, nodeID)
		local rank, y = node and node.activeRank, node and node.posY
		if canaccessvalue(rank) and canaccessvalue(y) and node.ID and node.ID ~= 0 then
			talents.read = talents.read + 1
			local taken = (rank or 0) > 0
			if taken and names then
				local name = EntryName(configID, node.activeEntry and node.activeEntry.entryID)
				if name then talents.taken[name] = true end
			end
			-- The tree's last node is its lowest; a bottom row of more than one counts as taken if any of it is.
			local tree
			for _, groupID in ipairs(node.groupIDs or {}) do tree = tree or trees[treeOf[groupID]] end
			if tree and (not tree.y or y > tree.y) then
				tree.y, tree.node, tree.taken = y, node, taken
			elseif tree and y == tree.y then
				tree.taken = tree.taken or taken
			end
		end
	end
	if talents.read == 0 then return nil end
	for _, tree in ipairs(trees) do
		if not tree.node then return talents end -- a tree with no nodes: the trees can't be told apart
		if names then
			local entryID = tree.node.activeEntry and tree.node.activeEntry.entryID or (tree.node.entryIDs or {})[1]
			tree.capstone = EntryName(configID, entryID)
		end
		tree.y, tree.node = nil, nil
	end
	if trees[1] then talents.trees = trees end
	return talents
end

-- The player's own talents, or an inspected player's; with `names` for the probe in TestCommands.lua.
function ns.ReadTalents(inspect, names)
	local ok, talents = pcall(ReadTalents, inspect and INSPECT_CONFIG or C_ClassTalents.GetActiveConfigID(), names)
	if ok then return talents end
end

-- The role a class's talents give: the role of the tree whose last node is taken. Otherwise nil and why: "ambiguous"
-- if that capstone leaves more than one, "nocapstone" if the talents don't say, or "unreadable" if the trees can't be
-- told apart.
local function TalentRole(class, talents)
	local capstones = CAPSTONES[class]
	if not (talents.trees and #talents.trees == #capstones) then return nil, "unreadable" end
	for index, tree in ipairs(talents.trees) do
		if tree.taken then
			local role = capstones[index]
			if type(role) == "table" then return nil, "ambiguous" end
			return role
		end
	end
	return nil, "nocapstone"
end

-- The player's own role and gear's say are asked for often (the Raid tab, the roles the writer sends), and each
-- means reading the whole talent tree (which costs the game's own tables for every node, 150 KB a read on the beta),
-- or every item worn: the answer is kept until the talents or gear change. One that can't be settled yet (talents
-- not loaded, or gear still loading) isn't kept, so it's read again next time.
local mine -- { role, why, read, gear, gearRead }
local function ForgetMine() mine = nil end
for _, event in ipairs({ "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "TRAIT_CONFIG_UPDATED",
	"PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED" }) do
	ns.On(event, ForgetMine)
end
local function Mine()
	mine = mine or {}
	return mine
end

-- The player's role as their talents suggest, for a class that can fill more than one; nil until the client has
-- their talents. Without one, nil and why (a key of ns.UNKNOWN_REASONS).
-- Third, whether the answer will hold until the talents change.
local function ReadMyRole()
	local _, class = UnitClass("player")
	if not CAPSTONES[class] then return nil, nil, true end
	if not C_SpecializationInfo.IsInitialized() then return nil, nil, false end
	local talents = ns.ReadTalents()
	if talents then
		local role, why = TalentRole(class, talents)
		return role, why, why ~= "unreadable"
	end
	return nil, "unreadable", false
end

function ns.MyRole()
	local kept = Mine()
	if not kept.read then
		local role, why, settled = ReadMyRole()
		kept.role, kept.why, kept.read = role, why, settled
	end
	return kept.role, kept.why
end

-- Gear ----------------------------------------------------------------------------------------------------------------

-- The role a raider's gear says, between the two their ambiguous capstone leaves open: tank if it suits tanking better
-- than damage, by the item roles' stat costs and wants (Roster.lua). Nil if their gear can't be read, and true as a
-- second value if some of it is still loading.
local function GearRole(unit, class)
	if not AMBIGUOUS[class] then return nil end
	local fits, loading = ns.GearFits(unit, class, AMBIGUOUS[class])
	if not fits then return nil, loading end
	return fits.TANK > fits.DAMAGER and "TANK" or "DAMAGER", loading
end

-- The role the player's own gear says, when their talents are ambiguous.
function ns.MyGearRole()
	local _, why = ns.MyRole()
	if why ~= "ambiguous" then return nil end
	local kept = Mine()
	if not kept.gearRead then
		local _, class = UnitClass("player")
		local role, loading = GearRole("player", class)
		kept.gear, kept.gearRead = role, not loading
	end
	return kept.gear
end

-- Roles ---------------------------------------------------------------------------------------------------------

-- A raider's role is, first, an officer's say on the Raid tab; or what their talents make certain: the role their own
-- client worked out and told the group (ns.ToldRole), or for players without the addon, the one an inspect read; or
-- else the one Blizzard's role menu gives them. A class with one role always has it, and is never asked or inspected. Apart from an officer's say, a role is kept from the first time a roll
-- uses it, so swapping roles or specs doesn't dodge the off-spec penalty. Anyone else's role is unknown, and rolls
-- use their class's fallback role (ns.FallbackRole) until it's found.
local roles, sources, told, inspected = {}, {}, {}, {}
local gear = {} -- guid -> the role their gear says, when their talents are ambiguous (told by their client, or inspected)
local why = {} -- guid -> what went wrong looking at their talents (a key of ns.UNKNOWN_REASONS), until it goes right
-- The roles the writer last told the group (guid -> { role, source }, or { false, why } if unknown), which it knows
-- best: other clients show these.
local writerRoles = {}

-- Officers' say, kept through a reload until the player leaves the group: guid -> { role, by }.
local function Overrides()
	return ns.saved and ns.saved.roleOverrides or {}
end

local function Changed()
	ns.Fire("ROLES_CHANGED")
end

-- The roles a member's class can fill, if it can fill more than one.
local function Choices(member)
	local fills = member and CLASS_ROLES[member.class]
	if fills and next(fills, next(fills)) then return fills end
end
ns.RoleChoices = Choices

-- The role the raid leader gave a member, if their class can fill it.
local function AssignedRole(member)
	local fills = CLASS_ROLES[member.class]
	local role = UnitGroupRolesAssigned(member.unit)
	if canaccessvalue(role) and ns.ROLE_NAMES[role] and (not fills or fills[role]) then return role end
end

-- A guild member's last known role, from the ledger (6.1), if it's one their ambiguous talents leave open.
local function LastKnown(member)
	local last = ns.ledger and ns.ledger:LastRole(member.guid)
	local open = AMBIGUOUS[member.class]
	if last and open and open[last] then return last end
end

-- A member's role as things stand, and where it came from, apart from an officer's say.
local function Resolve(member)
	local fills = CLASS_ROLES[member.class]
	if fills and not Choices(member) then return (next(fills)), "class" end
	if member.guid == UnitGUID("player") then
		local role = ns.MyRole()
		if role then return role, "talents" end
	end
	if told[member.guid] then return told[member.guid], "talents" end
	if inspected[member.guid] then return inspected[member.guid], "inspect" end
	local role = AssignedRole(member)
	if role then return role, "raid" end
	role = member.guid == UnitGUID("player") and ns.MyGearRole() or gear[member.guid]
	if role then return role, "gear" end
	if ns.RoleReason(member.guid) == "ambiguous" then
		role = LastKnown(member)
		if role then return role, "known" end
	end
end

-- The role a roll uses, and whether it's only the fallback for a role that's unknown.
function ns.RoleOf(guid)
	local override = Overrides()[guid]
	if override then return override.role end
	if not roles[guid] then
		local member = ns.GroupMember(guid)
		if not member then return nil end
		local role, source = Resolve(member)
		if source == "class" then return role end
		if not role then return ns.FallbackRole(member.class, ns.RoleReason(guid)), true end
		roles[guid], sources[guid] = role, source
		Changed()
	end
	return roles[guid]
end

-- What went wrong the last time a raider's talents were looked at, if anything did: why their role is unknown (the
-- writer's account, unless this client knows better), or why an inspect an officer asked for didn't find it.
function ns.RoleReason(guid)
	if guid == UnitGUID("player") then return select(2, ns.MyRole()) end
	local fromWriter = not ns.AmWriter() and writerRoles[guid]
	return why[guid] or (fromWriter and fromWriter[1] == false and fromWriter[2]) or nil
end

-- The roles an officer can give a raider: the two their capstone leaves open if it's ambiguous, else any their class
-- can fill.
function ns.RoleOptions(member)
	return ns.RoleReason(member.guid) == "ambiguous" and AMBIGUOUS[member.class] or Choices(member)
end

-- The role to show for a raider, where it came from (a key of ns.ROLE_SOURCES), and the officer who set it, if one
-- did. Clients other than the writer show the writer's view when it has one, as it inspects players.
function ns.RoleInfo(guid, ignoreOfficer)
	local override = not ignoreOfficer and Overrides()[guid]
	if override then return override.role, "officer", override.by end
	local member = ns.GroupMember(guid)
	if member and not Choices(member) and CLASS_ROLES[member.class] then return (next(CLASS_ROLES[member.class])), "class" end
	if roles[guid] then return roles[guid], sources[guid] end
	local fromWriter = not ns.AmWriter() and writerRoles[guid]
	if fromWriter and fromWriter[1] then return fromWriter[1], fromWriter[2] end
	if member then return Resolve(member) end
end

-- The role a raider would have without an officer's say.
function ns.AutoRole(guid)
	return (ns.RoleInfo(guid, true))
end

-- The writer's view of every role it knows, for the group (an officer's say goes separately).
function ns.RoleMap()
	local map = {}
	for _, member in ipairs(ns.GroupMembers()) do
		local role, source = ns.RoleInfo(member.guid)
		if Choices(member) and source ~= "officer" then
			if role then
				map[member.guid] = { role, source }
			elseif why[member.guid] then
				map[member.guid] = { false, why[member.guid] }
			end
		end
	end
	return map
end

-- The writer's view of the roles, from its message.
function ns.SetWriterRoles(map)
	if type(map) ~= "table" then return end
	writerRoles = {}
	for guid, entry in pairs(map) do
		local known = ns.ROLE_NAMES[entry[1]] and ns.ROLE_SOURCES[entry[2]] ~= nil
		local unknown = entry[1] == false and ns.UNKNOWN_REASONS[entry[2]]
		if type(guid) == "string" and type(entry) == "table" and (known or unknown) then
			writerRoles[guid] = entry
		end
	end
	Changed()
end

-- Gear's say on a raider's role, if their talents are ambiguous and it's one of the two they leave open.
local function SetGear(member, reason, role)
	local open = reason == "ambiguous" and AMBIGUOUS[member.class]
	gear[member.guid] = open and open[role] and role or nil
end

-- A role a player's client told the group, from their talents, or why their talents don't settle one (and, if they're
-- ambiguous, what the player's gear says).
function ns.ToldRole(sender, role, reason, gearRole)
	local member = ns.GroupMember(sender)
	local fills = Choices(member)
	if fills and fills[role] then
		told[member.guid], why[member.guid], gear[member.guid] = role, nil, nil
		Changed()
		ns.Fire("ROLE_FOUND", member.guid)
	elseif fills and SETTLED[reason] then
		why[member.guid] = reason
		SetGear(member, reason, gearRole)
		Changed()
	end
end

-- An officer's say on a raider's role (`by` is the officer), or nil to go back to working it out. It holds for every
-- roll from now on, including one that's open, until they leave the group. Returns whether it was taken.
function ns.ApplyRole(guid, role, by)
	local member = ns.GroupMember(guid)
	local fills = Choices(member)
	if not fills or (role ~= nil and not fills[role]) or not ns.saved then return false end
	ns.saved.roleOverrides[member.guid] = role and { role = role, by = by } or nil
	Changed()
	ns.Fire("ROLE_FOUND", member.guid, true)
	return true
end

-- Last known roles ---------------------------------------------------------------------------------------------------

-- The role a member's talents make certain, or an officer's say on it: the newest, even if a roll has used another.
local function CertainRole(member)
	local override = Overrides()[member.guid]
	if override then return override.role end
	if member.guid == UnitGUID("player") then return (ns.MyRole()) end
	return told[member.guid] or inspected[member.guid]
end

-- The writer keeps each guild member's last known role in the ledger, for when their talents are ambiguous
-- (4.6): it records a new one whenever their talents make a role certain or an officer sets one.
local function Remember(member)
	if not (member and Choices(member) and ns.ledger and ns.AmWriter() and ns.HoldsTable()) then return end
	if not ns.GuildMember(member.guid) then return end
	local role = CertainRole(member)
	if not role or ns.ledger:LastRole(member.guid) == role then return end
	ns.RecordChange(ns.NewChange({ op = "role", id = member.guid, role = ns.ROLE_CODES[role] }))
end

-- Everyone's, for a writer taking over.
function ns.RememberRoles()
	for _, member in ipairs(ns.GroupMembers()) do Remember(member) end
end

ns.Listen("ROLE_FOUND", function(guid) Remember(ns.GroupMember(guid)) end)
ns.On("PLAYER_TALENT_UPDATE", function() Remember(ns.GroupMember(UnitGUID("player"))) end)

-- Inspecting ---------------------------------------------------------------------------------------------------------

-- The writer inspects the raiders whose talents haven't settled their role, one at a time and out of combat: those
-- whose class has a choice of roles, whom no officer has given one, and whose client hasn't told it (they don't have
-- the addon), including those with a role from Blizzard's role menu, as talents come first. It starts a few seconds after the writer takes over or the group changes, so clients with
-- the addon answer first, and again whenever a roll starts. Someone out of range is tried next time; someone whose
-- talents still can't be read after a few inspects is left unknown. Any officer can also inspect one raider from the
-- Raid tab (a "manual" inspect), or every raider whose role is unknown ("Inspect Unknown", a sweep).
local INSPECT_WAIT = 5 -- seconds for clients with the addon to tell their roles first
local INSPECT_GAP = 1.5 -- seconds between inspects, which the server limits
local INSPECT_TIMEOUT = 3 -- seconds to wait for an inspect's answer
local INSPECT_TRIES = 3
local tries, inspectTimer = {}, nil
local inspecting, inspectKind -- the raider being inspected, and "auto", "manual" or "sweep"
local sweep -- while an officer's sweep is on: guid -> true for the raiders it's still to try, and counts

local function NeedsInspect(member)
	return Choices(member) ~= nil and member.guid ~= UnitGUID("player") and not roles[member.guid]
		and not told[member.guid] and not inspected[member.guid] and not Overrides()[member.guid]
		and not SETTLED[why[member.guid]]
		and (tries[member.guid] or 0) < INSPECT_TRIES
end

-- The game's own inspect window, and its talent window showing someone's talents, share the one inspect, so nothing
-- is inspected in the background while either is open.
local function InspectWindowOpen()
	return (InspectFrame ~= nil and InspectFrame:IsShown())
		or (PlayerSpellsFrame ~= nil and PlayerSpellsFrame:IsShown() and PlayerSpellsFrame:IsInspecting())
end

local InspectNext

-- Inspects the next raider still to find out about, after `delay` seconds: for the writer, or an officer's sweep.
local function Schedule(delay)
	if inspectTimer or inspecting or not (sweep or (ns.AmWriter and ns.AmWriter())) then return end
	inspectTimer = C_Timer.NewTimer(delay, InspectNext)
end

-- Starts inspecting: `now`, or after giving clients with the addon time to tell their roles.
function ns.InspectRoles(now)
	Schedule(now and 0 or INSPECT_WAIT)
end

-- Whether a raider is being inspected, for the Raid tab.
function ns.IsInspecting(guid)
	return inspecting ~= nil and inspecting == guid
end

-- Whether an officer's sweep is on, for the Raid tab's button.
function ns.IsSweeping()
	return sweep ~= nil
end

-- Whether an officer's inspect or sweep is under way, when the Raid tab starts no other until it's over. The writer's
-- own inspects in the background don't count: an officer's takes their place.
function ns.InspectBusy()
	return sweep ~= nil or (inspecting ~= nil and inspectKind ~= "auto")
end

local function Tell(guid, role, reason, gearRole)
	if not ns.AmWriter() then ns.TellInspected(guid, role, reason, gearRole) end
end

-- A sweep that's tried everyone: how it went, in chat.
local function EndSweep()
	local found, tried = sweep.found, sweep.tried
	sweep = nil
	Changed()
	ns.Print(L.SWEEP_DONE:format((tried == 1 and L.SWEEP_RAIDER or L.SWEEP_RAIDERS):format(tried),
		(found == 1 and L.SWEEP_ROLE or L.SWEEP_ROLES):format(found)))
end

-- An inspect that's over, or that got no answer in time.
local function Done(guid, answered)
	if inspecting ~= guid then return end
	local kind = inspectKind
	inspecting, inspectKind = nil, nil
	if not answered then
		why[guid] = "noreply"
		if kind ~= "auto" then Tell(guid, nil, "noreply") end
		if kind == "manual" then
			local member = ns.GroupMember(guid)
			if member then ns.Print(("%s: %s"):format(ns.ColoredName(guid, member.name), ReasonText("noreply"))) end
		end
	end
	Changed()
	if not InspectWindowOpen() then ClearInspectPlayer() end
	Schedule(INSPECT_GAP)
end

local function Inspect(member, kind)
	inspecting, inspectKind = member.guid, kind
	if kind == "auto" then tries[member.guid] = (tries[member.guid] or 0) + 1 end
	Changed()
	NotifyInspect(member.unit)
	C_Timer.After(INSPECT_TIMEOUT, function() Done(member.guid) end)
end

-- Whether a member's unit is still them: raid units shift as people leave.
local function UnitIsMember(member)
	local unitGuid = UnitGUID(member.unit)
	return canaccessvalue(unitGuid) and unitGuid == member.guid
end

InspectNext = function()
	inspectTimer = nil
	local writer = ns.AmWriter()
	if not (writer or sweep) then return end
	if InCombatLockdown() or InspectWindowOpen() then return Schedule(INSPECT_WAIT) end
	for _, member in ipairs(ns.GroupMembers()) do
		local guid = member.guid
		local swept = sweep and sweep[guid]
		if swept or (writer and NeedsInspect(member) and UnitIsMember(member)) then
			if swept then
				sweep[guid] = nil
				sweep.tried = sweep.tried + 1
			end
			if not UnitIsMember(member) then
				-- Gone from the group, or a made-up raider: nothing to inspect.
				if swept then sweep.tried = sweep.tried - 1 end
			elseif not CanInspect(member.unit) then
				if why[guid] ~= "far" then
					why[guid] = "far"
					Changed()
				end
				if swept then Tell(guid, nil, "far") end
			else
				return Inspect(member, swept and "sweep" or "auto")
			end
		end
	end
	if sweep then EndSweep() end
end

-- A role read from a raider's talents. One an officer asked for replaces an earlier inspect's, or one from Blizzard's
-- role menu, even one a roll has used, as it's newer and certain; the raider's own client still comes first.
function ns.ApplyInspect(guid, role, asked)
	local member = ns.GroupMember(guid)
	local fills = Choices(member)
	if not (fills and fills[role]) then return end
	inspected[member.guid], why[member.guid], gear[member.guid] = role, nil, nil
	if asked and (sources[member.guid] == "inspect" or sources[member.guid] == "raid") then roles[member.guid] = role end
	Changed()
	ns.Fire("ROLE_FOUND", member.guid, asked)
end

-- Why an officer's inspect couldn't find a raider's role, sent to the writer (ns.TellInspected), with what their gear
-- says if their talents are ambiguous.
function ns.InspectFailed(guid, reason, gearRole)
	local member = ns.GroupMember(guid)
	if not (Choices(member) and ns.UNKNOWN_REASONS[reason]) or roles[guid] or told[guid] or inspected[guid] then return end
	why[guid] = reason
	SetGear(member, reason, gearRole)
	Changed()
end

ns.On("INSPECT_READY", function(guid)
	if guid ~= inspecting then return end
	local member = ns.GroupMember(guid)
	local talents = member and CAPSTONES[member.class] and C_Traits.HasValidInspectData() and ns.ReadTalents(true)
	local role, reason, gearRole, loading
	if talents then role, reason = TalentRole(member.class, talents) else reason = "unreadable" end
	-- Ambiguous talents: their gear, read from the same inspect, says which.
	if reason == "ambiguous" then gearRole, loading = GearRole(member.unit, member.class) end
	local kind = inspectKind
	if role then
		-- A role an officer's own inspect is sure of replaces one an officer set by hand, for everyone.
		if kind == "manual" and Overrides()[guid] then ns.SetRole(guid, nil) end
		ns.ApplyInspect(guid, role, kind ~= "auto")
		if sweep and kind == "sweep" then sweep.found = sweep.found + 1 end
	elseif member then
		-- Talents that can't be read say nothing; ones that can, without a single role, need their gear's say or an
		-- officer's. Gear still loading is looked at again next time.
		why[guid] = reason
		SetGear(member, reason, gearRole)
		if SETTLED[reason] and not (loading and not gearRole) then tries[guid] = INSPECT_TRIES end
		if gearRole then ns.Fire("ROLE_FOUND", guid) end
		Changed()
	end
	if member and kind ~= "auto" then
		Tell(guid, role, role == nil and reason or nil, gearRole)
		if kind == "manual" then
			local name = ns.ColoredName(guid, member.name)
			if role then
				ns.Print(L["TALENTS_SAY_" .. role]:format(name))
			elseif gearRole then
				ns.Print(L["GEAR_SAYS_" .. gearRole]:format(name))
			else
				ns.Print(("%s: %s"):format(name, ReasonText(reason)))
			end
		end
	end
	Done(guid, true)
end)

-- Inspects a raider straight away, for an officer on the Raid tab: their talents are read for their role, whatever
-- is known already, and the result printed (and sent to the writer, who tells the group).
function ns.InspectRaider(member)
	if ns.InspectBusy() or not Choices(member) or not UnitIsMember(member) then return end
	if not CanInspect(member.unit) then
		why[member.guid] = "far"
		Changed()
		Tell(member.guid, nil, "far")
		return ns.Print(("%s: %s"):format(ns.ColoredName(member.guid, member.name), ReasonText("far")))
	end
	if inspectTimer then
		inspectTimer:Cancel()
		inspectTimer = nil
	end
	Inspect(member, "manual")
end

-- The raiders whose role is unknown, for "Inspect Unknown": those whose class has a choice of roles and whose role
-- nobody knows, set or found. Ones already known are left alone.
function ns.UnknownRaiders()
	local unknown = {}
	for _, member in ipairs(ns.GroupMembers()) do
		if Choices(member) and member.guid ~= UnitGUID("player") and not ns.RoleInfo(member.guid) then unknown[#unknown + 1] = member end
	end
	return unknown
end

-- An officer's "Inspect Unknown": every raider whose role is unknown is inspected in turn, whatever was tried before.
function ns.InspectUnknown()
	if ns.InspectBusy() then return end
	local unknown = ns.UnknownRaiders()
	if not unknown[1] then return end
	sweep = { tried = 0, found = 0 }
	for _, member in ipairs(unknown) do
		sweep[member.guid] = true
		tries[member.guid] = 0
	end
	Changed()
	if inspectTimer then
		inspectTimer:Cancel()
		inspectTimer = nil
	end
	Schedule(0)
end

-- Everything about roles is for the group, so it goes when the player leaves it, or logs in outside one (and with
-- /pl test reset).
function ns.ForgetRoles()
	roles, sources, told, inspected, tries, writerRoles, why, gear = {}, {}, {}, {}, {}, {}, {}, {}
	inspecting, inspectKind, sweep = nil, nil, nil
	if inspectTimer then
		inspectTimer:Cancel()
		inspectTimer = nil
	end
	if ns.saved then ns.saved.roleOverrides = {} end
	Changed()
end

ns.On("GROUP_ROSTER_UPDATE", function()
	if not IsInGroup() and not ns.IsTestMode() then return ns.ForgetRoles() end
	Changed()
	ns.InspectRoles()
end)
ns.On("PLAYER_ENTERING_WORLD", function()
	if not IsInGroup() and not ns.IsTestMode() then ns.ForgetRoles() end
end)
