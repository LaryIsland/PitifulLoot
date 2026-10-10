local _, ns = ...

-- Who is in the group and the guild by name and GUID, which guild members are officers (6.3), each raider's role
-- for off-spec rolls (4.6), and what an item says about who can use it (4.5) and which roles it's for.

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

-- Items that are nobody's role in particular: cosmetics, and anything that isn't gear (mounts, pets, recipes).
-- Anyone can roll on them, and nobody is off-spec for them.
function ns.ForEveryone(item)
	if C_Item.IsCosmeticItem and C_Item.IsCosmeticItem(item) then return true end
	if C_Item.IsEquippableItem and not C_Item.IsEquippableItem(item) then return true end
	return false
end

-- Who can use what (4.5). Forever's items aren't tied to specs, so it's worked out from the item itself: a
-- "Classes:" line on its tooltip limits it to those classes, and otherwise its armour or weapon type has to be one the
-- class can equip, as in the original game. Rings, necks, trinkets, cloaks and off-hand items suit anyone. To be
-- tuned as the beta shows what's wrong.
local ITEM_ARMOR, ITEM_WEAPON = 4, 2 -- Enum.ItemClass
local ARMOR = { cloth = 1, leather = 2, mail = 3, plate = 4, shield = 6, libram = 7, idol = 8, totem = 9 }
local WEAPON = {
	axe = 0, axe2h = 1, bow = 2, gun = 3, mace = 4, mace2h = 5, polearm = 6, sword = 7, sword2h = 8, staff = 10,
	fist = 13, dagger = 15, thrown = 16, crossbow = 18, wand = 19,
}
local ANY_ARMOR, ANY_WEAPON = { [0] = true }, { [14] = true, [20] = true } -- miscellaneous, and fishing poles
local PROFICIENCY = {
	WARRIOR = {
		armor = { "cloth", "leather", "mail", "plate", "shield" },
		weapons = { "axe", "axe2h", "bow", "gun", "mace", "mace2h", "polearm", "sword", "sword2h", "staff", "fist", "dagger", "thrown", "crossbow" },
	},
	PALADIN = {
		armor = { "cloth", "leather", "mail", "plate", "shield", "libram" },
		weapons = { "axe", "axe2h", "mace", "mace2h", "polearm", "sword", "sword2h" },
	},
	HUNTER = {
		armor = { "cloth", "leather", "mail" },
		weapons = { "axe", "axe2h", "bow", "gun", "polearm", "sword", "sword2h", "staff", "fist", "dagger", "thrown", "crossbow" },
	},
	ROGUE = { armor = { "cloth", "leather" }, weapons = { "bow", "gun", "mace", "sword", "fist", "dagger", "thrown", "crossbow" } },
	PRIEST = { armor = { "cloth" }, weapons = { "mace", "staff", "dagger", "wand" } },
	SHAMAN = {
		armor = { "cloth", "leather", "mail", "shield", "totem" },
		weapons = { "axe", "axe2h", "mace", "mace2h", "staff", "fist", "dagger" },
	},
	MAGE = { armor = { "cloth" }, weapons = { "sword", "staff", "dagger", "wand" } },
	WARLOCK = { armor = { "cloth" }, weapons = { "sword", "staff", "dagger", "wand" } },
	DRUID = { armor = { "cloth", "leather", "idol" }, weapons = { "mace", "mace2h", "staff", "fist", "dagger" } },
}
local equips = {} -- class -> { [item class] = { [subclass] = true } }
for class, kinds in pairs(PROFICIENCY) do
	local armor, weapons = setmetatable({}, { __index = ANY_ARMOR }), setmetatable({}, { __index = ANY_WEAPON })
	for _, name in ipairs(kinds.armor) do armor[ARMOR[name]] = true end
	for _, name in ipairs(kinds.weapons) do weapons[WEAPON[name]] = true end
	equips[class] = { [ITEM_ARMOR] = armor, [ITEM_WEAPON] = weapons }
end

-- A format string from the game's own text as a pattern, its %s and %d capturing.
local function Pattern(format)
	return "^" .. format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%?([sd])", "(.+)")
end
local CLASSES_LINE = ITEM_CLASSES_ALLOWED and Pattern(ITEM_CLASSES_ALLOWED)

-- The classes an item's tooltip limits it to, as class file names, or false if it doesn't. Only kept once the item's
-- data has loaded, as the tooltip is incomplete before then.
local classNames -- localised class name -> file name
local restrictions = {}
local function ClassesAllowed(item)
	if restrictions[item] ~= nil then return restrictions[item] end
	if not (CLASSES_LINE and C_TooltipInfo and C_TooltipInfo.GetItemByID) then return false end
	if not classNames then
		classNames = {}
		for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
			if type(names) == "table" then
				for file, name in pairs(names) do classNames[name] = file end
			end
		end
	end
	local allowed = false
	local data = C_TooltipInfo.GetItemByID(item)
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText
		local list = canaccessvalue(text) and type(text) == "string" and text:match(CLASSES_LINE)
		if list then
			allowed = {}
			for name in list:gmatch("[^,]+") do
				name = name:match("^%s*(.-)%s*$")
				allowed[classNames[name] or name:upper()] = true
			end
		end
	end
	if C_Item.GetItemInfo(item) then restrictions[item] = allowed end
	return allowed
end

local function CanEquip(class, item)
	local classSets = equips[class]
	if not classSets then return true end
	local _, _, _, equipLoc, _, itemClass, subclass = C_Item.GetItemInfoInstant(item)
	if equipLoc == "INVTYPE_CLOAK" then return true end
	local set = classSets[itemClass]
	if not set or subclass == nil then return true end
	return set[subclass] == true
end

-- Whether the player's class can use the item at all (4.5). Anything the client can't say counts as usable.
function ns.CanUse(guid, item)
	local member = ns.GroupMember(guid)
	local class = member and member.class
	if not class then return true end
	local allowed = ClassesAllowed(item)
	if allowed and not allowed[class] then return false end
	if ns.ForEveryone(item) then return true end
	return CanEquip(class, item)
end

-- Roles --------------------------------------------------------------------------------------------------------

-- The roles each class can fill. A class with one role is always that role; a role its class can't fill is ignored.
local CLASS_ROLES = {
	WARRIOR = { TANK = true, DAMAGER = true },
	PRIEST = { HEALER = true, DAMAGER = true },
	PALADIN = { TANK = true, HEALER = true, DAMAGER = true },
	SHAMAN = { TANK = true, HEALER = true, DAMAGER = true },
	DRUID = { TANK = true, HEALER = true, DAMAGER = true },
	MAGE = { DAMAGER = true }, WARLOCK = { DAMAGER = true }, ROGUE = { DAMAGER = true }, HUNTER = { DAMAGER = true },
}

-- Each raider's role is the one the raid leader gave them in the game's role menu, kept from the first time it's
-- seen so swapping roles doesn't dodge the off-spec penalty; a class that can only do damage always does. Someone
-- else with no role is unknown, and counts as main-spec until the writer says otherwise.
local roles = {}

function ns.RoleOf(guid)
	if not roles[guid] then
		local member = ns.GroupMember(guid)
		local fills = member and CLASS_ROLES[member.class]
		local role = member and UnitGroupRolesAssigned(member.unit)
		if canaccessvalue(role) and ns.ROLE_NAMES[role] and (not fills or fills[role]) then
			roles[guid] = role
		elseif fills and not next(fills, next(fills)) then
			return (next(fills))
		end
	end
	return roles[guid]
end

ns.On("GROUP_ROSTER_UPDATE", function()
	if not IsInGroup() then roles = {} end
end)

-- What an item's stats say about the roles it's for. Strength and agility suit tanks too, so plate with defense
-- reads as tank and damage. To be tuned.
local STAT_ROLES = {
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = { "TANK" }, ITEM_MOD_DODGE_RATING_SHORT = { "TANK" },
	ITEM_MOD_PARRY_RATING_SHORT = { "TANK" }, ITEM_MOD_BLOCK_RATING_SHORT = { "TANK" }, ITEM_MOD_BLOCK_VALUE_SHORT = { "TANK" },
	ITEM_MOD_SPIRIT_SHORT = { "HEALER" }, ITEM_MOD_MANA_REGENERATION_SHORT = { "HEALER" },
	ITEM_MOD_SPELL_HEALING_DONE_SHORT = { "HEALER" },
	ITEM_MOD_INTELLECT_SHORT = { "HEALER", "DAMAGER" },
	ITEM_MOD_STRENGTH_SHORT = { "DAMAGER" }, ITEM_MOD_AGILITY_SHORT = { "DAMAGER" }, ITEM_MOD_ATTACK_POWER_SHORT = { "DAMAGER" },
	ITEM_MOD_HIT_RATING_SHORT = { "DAMAGER" }, ITEM_MOD_CRIT_RATING_SHORT = { "DAMAGER" },
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = { "DAMAGER" }, ITEM_MOD_SPELL_POWER_SHORT = { "DAMAGER" },
}

local function SuggestedRoles(item)
	local _, link = C_Item.GetItemInfo(item)
	local stats = link and C_Item.GetItemStats(link)
	local suits
	for stat in pairs(stats or {}) do
		for _, role in ipairs(STAT_ROLES[stat] or {}) do
			suits = suits or {}
			suits[role] = true
		end
	end
	return suits
end

-- The roles an item is for, as a set, or nil for any role: an officer's say, recorded in the ledger, or
-- else what its stats suggest. Items that aren't gear, or whose stats say nothing, suit any role.
function ns.ItemRoles(item)
	if ns.ForEveryone(item) then return nil end
	local state = ns.ledger and ns.ledger.state
	local suits = state and state.roles[item]
	if suits == nil then suits = SuggestedRoles(item) end
	if not suits or next(suits) == nil then return nil end
	for _, role in ipairs(ns.ROLE_ORDER) do
		if not suits[role] then return suits end
	end
	return nil
end

-- Whether the item is off-spec for the player: true or false, or nil if their role isn't known.
function ns.IsOffSpec(guid, item)
	local suits = ns.ItemRoles(item)
	if not suits then return false end
	local role = ns.RoleOf(guid)
	if not role then return nil end
	return not suits[role]
end
