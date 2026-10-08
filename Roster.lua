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

-- Names and GUIDs can be secret in combat; if any are, the group is read again next time it's needed.
local function RebuildGroup()
	group = { byName = {}, byGuid = {}, list = {} }
	groupDirty = false
	for _, unit in ipairs(GroupUnits()) do
		local guid = UnitGUID(unit)
		local name, realm = UnitName(unit)
		if not canaccessvalue(guid) or not canaccessvalue(name) or not canaccessvalue(realm) then
			groupDirty = true
		elseif guid and name then
			local _, class, classID = UnitClass(unit)
			local member = { unit = unit, guid = guid, name = name, class = class, classID = classID }
			group.byGuid[guid] = member
			group.byName[name] = member
			if realm and realm ~= "" then group.byName[name .. "-" .. realm] = member end
			group.list[#group.list + 1] = member
			ns.RememberName(guid, name)
		end
	end
end

local function RebuildGuild()
	guild = { byName = {}, byGuid = {} }
	for i = 1, GetNumGuildMembers() do
		local name, _, rank, _, _, _, _, _, _, _, class, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		if name then
			local member = { name = name, rank = rank, guid = guid, class = class }
			guild.byName[name] = member
			guild.byName[ns.ShortName(name)] = guild.byName[ns.ShortName(name)] or member
			if guid then
				guild.byGuid[guid] = member
				ns.RememberName(guid, ns.ShortName(name))
			end
		end
	end
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
end

function ns.IsOfficer(name)
	local member = ns.GuildMember(name)
	return member ~= nil and member.rank ~= nil and member.rank <= ns.settings.officerRank
end

-- A player's GUID from their name, looking in the group and then the guild.
function ns.FindPlayer(name)
	local member = ns.GroupMember(name) or ns.GuildMember(name)
	return member and member.guid
end

-- Names are kept locally so pity can be shown for players who aren't online.
function ns.RememberName(guid, name)
	if ns.db and guid and name then ns.db.names[guid] = name end
end

function ns.NameOf(guid)
	local member = ns.GroupMember(guid)
	if member then return member.name end
	if ns.db and ns.db.names[guid] then return ns.db.names[guid] end
	local name = select(6, GetPlayerInfoByGUID(guid))
	return name or guid
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

local function ItemSpecs(item)
	local specs = C_Item.GetItemSpecInfo(item)
	if specs and #specs > 0 then return specs end
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
