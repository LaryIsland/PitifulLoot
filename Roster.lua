local _, ns = ...

-- Who is in the group and the guild by name and GUID, which guild members are officers (6.3), what each raider's
-- spec is for off-spec rolls (4.6), and what an item says about who can use it (4.5).

local INSPECT_INTERVAL = 2
local INSPECT_TIMEOUT = 5

local group, guild
local groupDirty, guildDirty = true, true

local function GroupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
	else
		units[1] = "player"
		for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
	end
	return units
end

-- A unit's full name. In Forever UnitName gives the first name and the surname separately, and the game shows them
-- together, as roll messages do ("Lary Island").
function ns.FullUnitName(unit)
	local name, surname = UnitName(unit)
	if not canaccessvalue(name) or not canaccessvalue(surname) then return nil, true end
	if name and surname and surname ~= "" then return name .. " " .. surname end
	return name
end

-- Names and GUIDs can be secret in combat; if any are, the group is read again next time it's needed. Members are
-- found by their full name and by their first name alone, as addon messages may give either.
local function RebuildGroup()
	group = { byName = {}, byGuid = {}, list = {} }
	groupDirty = false
	for _, unit in ipairs(GroupUnits()) do
		local guid = UnitGUID(unit)
		local name, secret = ns.FullUnitName(unit)
		if secret or not canaccessvalue(guid) then
			groupDirty = true
		elseif guid and name then
			local _, class, classID = UnitClass(unit)
			local member = { unit = unit, guid = guid, name = name, class = class, classID = classID }
			group.byGuid[guid] = member
			group.byName[name] = member
			local first = name:match("^(%S+)")
			group.byName[first] = group.byName[first] or member
			group.list[#group.list + 1] = member
			ns.RememberName(guid, name, class)
		end
	end
end

-- Officers are the ranks the guild gives officer privileges in its rank settings, which is what the game itself means
-- by an officer (6.3); the guild master always is one. If the client can't read a rank's settings, ranks 0 and 1 count.
local OFFICER_PRIVILEGES = 22 -- the rank flag behind GUILD_CONTROL_RANK_PERMISSION_HAS_OFFICER_PRIVLEGES
local FALLBACK_OFFICER_RANK = 1

local function IsOfficerRank(rank, known)
	if rank == 0 then return true end
	if known[rank] == nil then
		local ok, flags = pcall(C_GuildInfo.GuildControlGetRankFlags, rank + 1)
		if ok and type(flags) == "table" and flags[OFFICER_PRIVILEGES] ~= nil then
			known[rank] = flags[OFFICER_PRIVILEGES] == true
		else
			known[rank] = rank <= FALLBACK_OFFICER_RANK
		end
	end
	return known[rank]
end

local function RebuildGuild()
	guild = { byName = {}, byGuid = {}, onlineOfficers = {} }
	local officerRanks = {}
	for i = 1, GetNumGuildMembers() do
		local name, _, rank, _, _, _, _, _, online, _, class, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		if name then
			local member = { name = name, rank = rank, guid = guid, class = class, officer = rank ~= nil and IsOfficerRank(rank, officerRanks) }
			if member.officer and online then guild.onlineOfficers[#guild.onlineOfficers + 1] = member end
			guild.byName[name] = member
			local short = ns.ShortName(name)
			guild.byName[short] = guild.byName[short] or member
			local first = short:match("^(%S+)")
			guild.byName[first] = guild.byName[first] or member
			if guid then
				guild.byGuid[guid] = member
				-- The group's names are fuller (they have surnames), so a guild name doesn't replace one.
				if not (ns.saved and ns.saved.names[guid]) then ns.RememberName(guid, ns.ShortName(name), class) end
			end
		end
	end
	table.sort(guild.onlineOfficers, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.name < b.name
	end)
	guildDirty = false
end

ns.On("GROUP_ROSTER_UPDATE", function()
	groupDirty = true
	ns.Fire("ROSTER_CHANGED")
end)
ns.On("GUILD_ROSTER_UPDATE", function()
	guildDirty = true
	ns.Fire("ROSTER_CHANGED")
end)

function ns.GroupMembers()
	if groupDirty then RebuildGroup() end
	return group.list
end

-- A group member by GUID or name. Roll messages may show more of a name than UnitName does (a surname, a realm),
-- so the first word and the name without its realm are tried too.
---@param key string?
function ns.GroupMember(key)
	if not key then return nil end
	if groupDirty then RebuildGroup() end
	return group.byGuid[key] or group.byName[key] or group.byName[ns.ShortName(key)]
		or group.byName[key:match("^(%S+)") or ""]
end

---@param key string?
function ns.GuildMember(key)
	if not key then return nil end
	if guildDirty then RebuildGuild() end
	return guild.byGuid[key] or guild.byName[key] or guild.byName[ns.ShortName(key)]
		or guild.byName[key:match("^(%S+)") or ""]
end

function ns.IsOfficer(name)
	-- In test mode you count as an officer, as do players you've trusted with /pl test trust.
	if ns.IsTestMode() and name and (ns.IsMe(name) or ns.saved.testOfficers[ns.ShortName(name)]) then return true end
	local member = ns.GuildMember(name)
	return member ~= nil and member.officer == true
end

-- The officers online, highest rank first, then by name.
function ns.OnlineOfficers()
	if guildDirty then RebuildGuild() end
	return guild.onlineOfficers
end

-- A player's GUID from their name, looking in the group and then the guild.
function ns.FindPlayer(name)
	local member = ns.GroupMember(name) or ns.GuildMember(name)
	return member and member.guid
end

-- Names are kept locally so pity can be shown for players who aren't online.
-- Names and classes are kept locally so pity can be shown, class coloured, for players who aren't online.
function ns.RememberName(guid, name, class)
	if not (ns.saved and guid and name) then return end
	ns.saved.names[guid] = name
	if class then ns.saved.classes[guid] = class end
end

function ns.NameOf(guid)
	local member = ns.GroupMember(guid)
	if member then return member.name end
	if ns.saved and ns.saved.names[guid] then return ns.saved.names[guid] end
	local name = select(6, GetPlayerInfoByGUID(guid))
	return name or guid
end

-- A player's class file name ("WARRIOR"), from a GUID or a name, if anything knows it.
function ns.ClassOf(key)
	local member = ns.GroupMember(key) or ns.GuildMember(key)
	if member and member.class then return member.class end
	if ns.saved and ns.saved.classes[key] then return ns.saved.classes[key] end
	if type(key) == "string" and key:match("^Player%-") then return (select(2, GetPlayerInfoByGUID(key))) end
end

-- A player's full name from a GUID or any name they go by, for showing.
function ns.DisplayName(key)
	if type(key) ~= "string" then return key end
	if key:match("^Player%-") then return ns.NameOf(key) end
	local member = ns.GroupMember(key) or ns.GuildMember(key)
	return member and member.guid and ns.NameOf(member.guid) or key
end

-- A name in its class colour, from a GUID or a name.
function ns.ColoredName(key, name)
	name = name or ns.DisplayName(key)
	local color = RAID_CLASS_COLORS[ns.ClassOf(key) or ""]
	if not color then return name end
	return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, name)
end

-- Items ---------------------------------------------------------------------------------------------------------

function ns.ItemID(item)
	if type(item) == "number" then return item end
	if type(item) ~= "string" then return nil end
	return tonumber(item) or tonumber(item:match("item:(%d+)"))
end

function ns.ItemLink(item)
	local _, link = C_Item.GetItemInfo(item)
	return link or ("[item " .. item .. "]")
end

function ns.IsBoE(item)
	return select(14, C_Item.GetItemInfo(item)) == 2
end

-- Items that are nobody's spec in particular: cosmetics, and anything that isn't gear (mounts, pets, recipes).
-- Anyone can roll on them, and nobody is off-spec for them.
function ns.ForEveryone(item)
	if C_Item.IsCosmeticItem and C_Item.IsCosmeticItem(item) then return true end
	if C_Item.IsEquippableItem and not C_Item.IsEquippableItem(item) then return true end
	local specs = C_Item.GetItemSpecInfo(item)
	return not (specs and #specs > 0)
end

local function ItemSpecs(item)
	if ns.ForEveryone(item) then return nil end
	return C_Item.GetItemSpecInfo(item)
end

-- Whether the player's class can use the item at all (4.5). Anything the client can't say counts as usable.
function ns.CanUse(guid, item)
	local specs = ItemSpecs(item)
	local member = ns.GroupMember(guid)
	if not specs or not member or not member.classID then return true end
	for _, spec in ipairs(specs) do
		if C_SpecializationInfo.GetClassIDFromSpecID(spec) == member.classID then return true end
	end
	return false
end

-- Specs ---------------------------------------------------------------------------------------------------------

-- Each raider's spec, kept from the first time it's seen so swapping spec doesn't dodge the off-spec penalty (4.6).
-- Only the writer looks these up; the writer can correct any roll's off-spec flag.
local specs = {}
local queue, inspecting, ticker = {}, nil, nil

function ns.ResetSpecs()
	specs = {}
end

function ns.SpecOf(guid)
	if not specs[guid] and guid == UnitGUID("player") then
		local index = C_SpecializationInfo.GetSpecialization()
		local spec = index and C_SpecializationInfo.GetSpecializationInfo(index)
		if spec and spec > 0 then specs[guid] = spec end
	end
	return specs[guid]
end

-- Whether the item is off-spec for the player: true or false, or nil if their spec isn't known yet.
function ns.IsOffSpec(guid, item)
	local itemSpecs = ItemSpecs(item)
	if not itemSpecs then return false end
	local spec = ns.SpecOf(guid)
	if not spec then return nil end
	for _, s in ipairs(itemSpecs) do
		if s == spec then return false end
	end
	return true
end

local function InspectNext()
	if inspecting and GetTime() - inspecting.started < INSPECT_TIMEOUT then return end
	inspecting = nil
	if InCombatLockdown() then return end
	while queue[1] do
		local guid = table.remove(queue, 1)
		local member = ns.GroupMember(guid)
		if member and not specs[guid] and CanInspect(member.unit) then
			inspecting = { guid = guid, unit = member.unit, started = GetTime() }
			NotifyInspect(member.unit)
			return
		end
	end
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- Looks up the spec of everyone in the group not already known, one at a time.
function ns.InspectGroup()
	queue = {}
	for _, member in ipairs(ns.GroupMembers()) do
		if not ns.SpecOf(member.guid) then queue[#queue + 1] = member.guid end
	end
	if queue[1] and not ticker then ticker = C_Timer.NewTicker(INSPECT_INTERVAL, InspectNext) end
	InspectNext()
end

ns.On("INSPECT_READY", function(guid)
	if not inspecting or inspecting.guid ~= guid then return end
	local spec = C_SpecializationInfo.GetInspectSpecialization(inspecting.unit)
	if canaccessvalue(spec) and spec and spec > 0 then specs[guid] = spec end
	inspecting = nil
	ClearInspectPlayer()
end)
