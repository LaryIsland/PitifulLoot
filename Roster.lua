local _, ns = ...

-- Who is in the group and the guild by name and GUID, which guild members are officers (6.3), and what an item says
-- about who can use it (4.5) and which roles it's for (4.6). Each raider's own role is in Roles.lua.

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
	for index, unit in ipairs(GroupUnits()) do
		local guid = UnitGUID(unit)
		local name, secret = ns.FullUnitName(unit)
		if secret or not canaccessvalue(guid) then
			groupDirty = true
		elseif guid and name then
			local _, class, classID = UnitClass(unit)
			-- Their raid group (1 to 8); a party is all group 1.
			local subgroup = IsInRaid() and select(3, GetRaidRosterInfo(index)) or 1
			local member = { unit = unit, guid = guid, name = name, class = class, classID = classID, subgroup = subgroup or 1 }
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
	guild = { byName = {}, byGuid = {}, onlineOfficers = {}, officers = {} }
	local officerRanks = {}
	for i = 1, GetNumGuildMembers() do
		local name, _, rank, _, _, _, _, _, online, _, class, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		if name then
			local member = { name = name, rank = rank, guid = guid, class = class, officer = rank ~= nil and IsOfficerRank(rank, officerRanks) }
			if member.officer and online then guild.onlineOfficers[#guild.onlineOfficers + 1] = member end
			if member.officer then guild.officers[#guild.officers + 1] = member end
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

-- Every officer in the guild, online or not.
function ns.GuildOfficers()
	if guildDirty then RebuildGuild() end
	return guild.officers
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

-- Why the player can't use the item, if they can't (4.5): "cantuse" if their class can't wear or wield it, or
-- "notforclass" if it can but the item's stats aren't for it (below). Anything the client can't say counts as usable.
function ns.WhyCantUse(guid, item)
	local member = ns.GroupMember(guid)
	local class = member and member.class
	if not class then return nil end
	local allowed = ClassesAllowed(item)
	if allowed and not allowed[class] then return "cantuse" end
	if ns.ForEveryone(item) then return nil end
	if not CanEquip(class, item) then return "cantuse" end
	if not ns.ItemSuitsClass(item, class) then return "notforclass" end
end

-- Whether the player's class can use the item at all.
function ns.CanUse(guid, item)
	return ns.WhyCantUse(guid, item) == nil
end

-- Item roles ---------------------------------------------------------------------------------------------------

-- What an item's stats say about the roles it's for (4.6, `Notes/Item Roles Review.md`). Every item has a stat budget
-- from its item level, and each stat costs a set amount of it (the classic item level formula's costs); how much of the
-- budget went on what each role of each class wants says what the item is for. An item is for the role of the best fit
-- over every class that can use it, and any role within KEEP of it. Every number here is a first guess, to tune
-- against Forever's real items (`/pl test stats`).

-- What the game calls each stat (GetItemStats), as the stats below. Hit and crit are single stats in Forever; any
-- melee, ranged or spell kinds an item shows count as the one. "Damage and healing" (spell power) is one stat that
-- healers and damage alike want.
local STAT_KEYS = {
	ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
	ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi",
	ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
	ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_HIT_MELEE_RATING_SHORT = "hit", ITEM_MOD_HIT_RANGED_RATING_SHORT = "hit",
	ITEM_MOD_HIT_SPELL_RATING_SHORT = "hit",
	ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "crit", ITEM_MOD_CRIT_RANGED_RATING_SHORT = "crit",
	ITEM_MOD_CRIT_SPELL_RATING_SHORT = "crit",
	ITEM_MOD_EXPERTISE_RATING_SHORT = "expertise",
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "damage", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "healing",
	ITEM_MOD_SPELL_POWER_SHORT = "spellPower",
	ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defense", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
	ITEM_MOD_PARRY_RATING_SHORT = "parry", ITEM_MOD_BLOCK_RATING_SHORT = "block", ITEM_MOD_BLOCK_VALUE_SHORT = "blockValue",
	RESISTANCE1_NAME = "resistance", RESISTANCE2_NAME = "resistance", RESISTANCE3_NAME = "resistance",
	RESISTANCE4_NAME = "resistance", RESISTANCE5_NAME = "resistance", RESISTANCE6_NAME = "resistance",
	-- Seen on Forever's items (`/pl test stats`, 14 Oct): one school's spell damage, damage against a kind of creature,
	-- and health per 5 seconds. ITEM_MOD_<school>_RESISTANCE_SHORT repeats RESISTANCEn_NAME, so it's left out;
	-- RESISTANCE0_NAME is armor, all of it (the bonus can't be told from the base), so it's left out too.
	ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = "fireDamage", ITEM_MOD_FROST_DAMAGE_DONE_SHORT = "frostDamage",
	ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = "shadowDamage", ITEM_MOD_NATURE_DAMAGE_DONE_SHORT = "natureDamage",
	ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT = "arcaneDamage", ITEM_MOD_HOLY_DAMAGE_DONE_SHORT = "holyDamage",
	ITEM_MOD_ATTACK_POWER_VS_UNDEAD_SHORT = "creatureAp", ITEM_MOD_ATTACK_POWER_VS_DEMON_SHORT = "creatureAp",
	ITEM_MOD_ATTACK_POWER_VS_BEAST_SHORT = "creatureAp",
	ITEM_MOD_SPELL_DAMAGE_VS_ELEMENTAL_SHORT = "creatureDamage", ITEM_MOD_SPELL_DAMAGE_VS_UNDEAD_SHORT = "creatureDamage",
	ITEM_MOD_SPELL_DAMAGE_VS_DEMON_SHORT = "creatureDamage", ITEM_MOD_SPELL_DAMAGE_VS_BEAST_SHORT = "creatureDamage",
	ITEM_MOD_HEALTH_REGEN_SHORT = "hp5",
}
local SUMMED = { resistance = true } -- stats that add up across keys; the rest are one stat by several names
local WEAPON_DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
local RANGED = { [2] = true, [3] = true, [16] = true, [18] = true } -- bows, guns, thrown, crossbows
local WAND = 19

-- Each stat's cost, per point (per 1% for hit, crit, dodge, parry and block; per point of damage per second for weapon
-- damage, set so a raid weapon's damage counts for about a third as much as its other stats).
local COST = {
	str = 230, agi = 230, sta = 230, int = 230, spi = 230, resistance = 230,
	ap = 115, rap = 92, healing = 100, damage = 192, spellPower = 192, mp5 = 550, expertise = 550,
	creatureAp = 76, creatureDamage = 100, hp5 = 550, -- creature spell damage: a guess
	defense = 345, blockValue = 150, block = 1300, dodge = 2500, parry = 3600, hit = 2200, crit = 3200,
	weapon = 45, rangedWeapon = 45,
}

-- How much each role wants each stat, from 0 to 1, as { tank, healer, damage }, and the classes that want it
-- differently: CLASS_WANTS[stat][class] replaces the row, a number for every role, or a table by role.
local WANTS = {
	str = { 0.5, 0, 1 }, agi = { 0.6, 0, 0.7 }, sta = { 1, 0.2, 0.2 }, int = { 0.1, 1, 0.4 }, spi = { 0.05, 0.6, 0.2 },
	hit = { 0.5, 0, 1 }, crit = { 0.6, 0.7, 1 }, ap = { 0.4, 0, 1 }, rap = { 0, 0, 0 }, expertise = { 1, 0, 1 },
	damage = { 0, 0, 1 }, healing = { 0, 1, 0 }, spellPower = { 0, 1, 1 }, mp5 = { 0, 1, 0.5 }, hp5 = { 0.5, 0.2, 0.2 },
	creatureDamage = { 0, 0, 1 }, creatureAp = { 0.4, 0, 1 },
	defense = { 1, 0, 0 }, dodge = { 1, 0, 0 }, parry = { 1, 0, 0 }, block = { 1, 0, 0 }, blockValue = { 1, 0, 0 },
	resistance = { 1, 1, 1 }, weapon = { 0.6, 0, 1 }, rangedWeapon = { 0, 0, 0 },
}
local CASTERS = { PRIEST = 0, MAGE = 0, WARLOCK = 0 }
local NO_MANA = { WARRIOR = 0, ROGUE = 0 }
local CLASS_WANTS = {
	str = setmetatable({ ROGUE = { DAMAGER = 0.5 }, HUNTER = { DAMAGER = 0.5 } }, { __index = CASTERS }),
	agi = setmetatable({ ROGUE = { DAMAGER = 1 }, HUNTER = { DAMAGER = 1 } }, { __index = CASTERS }),
	int = setmetatable({ PALADIN = { TANK = 0.3, HEALER = 1, DAMAGER = 0.3 }, HUNTER = { TANK = 0.1, HEALER = 1, DAMAGER = 0.8 },
		SHAMAN = { TANK = 0.1, HEALER = 1, DAMAGER = 0.35 } }, { __index = NO_MANA }),
	spi = NO_MANA, mp5 = setmetatable({ PALADIN = { TANK = 0.3, HEALER = 1, DAMAGER = 0.5 } }, { __index = NO_MANA }),
	ap = CASTERS, weapon = CASTERS,
	rap = { HUNTER = { DAMAGER = 1 } }, rangedWeapon = { HUNTER = { DAMAGER = 1 } },
	expertise = CASTERS, -- hunters too: Forever's survival hunters fight in melee
	damage = { WARRIOR = 0, ROGUE = 0, HUNTER = 0, PALADIN = { TANK = 0.3, DAMAGER = 1 } },
}
CLASS_WANTS.creatureDamage, CLASS_WANTS.creatureAp = CLASS_WANTS.damage, CASTERS

-- One school's spell damage is for the classes that cast that school (as in the original game, which Forever keeps),
-- wanted as spell damage is; nothing for anyone else, so a mage can't need a shadow damage wand.
local SCHOOLS = {
	fire = { MAGE = true, WARLOCK = true, SHAMAN = true }, frost = { MAGE = true, SHAMAN = true },
	shadow = { PRIEST = true, WARLOCK = true }, nature = { DRUID = true, SHAMAN = true },
	arcane = { MAGE = true, DRUID = true }, holy = { PALADIN = true, PRIEST = true },
}
for school, casters in pairs(SCHOOLS) do
	local stat = school .. "Damage"
	COST[stat], WANTS[stat] = 159, WANTS.damage
	CLASS_WANTS[stat] = setmetatable({}, { __index = function(_, class)
		if casters[class] then return CLASS_WANTS.damage[class] end
		return 0
	end })
end
CLASS_WANTS.spellPower = { WARRIOR = 0, ROGUE = 0, HUNTER = 0, PALADIN = { TANK = 0.3, HEALER = 1, DAMAGER = 1 } }
local ROLE_INDEX = { TANK = 1, HEALER = 2, DAMAGER = 3 }

-- How much of an item a class's tank role can use, from 0 to 1, by what kind of item it is:
-- * Warrior, paladin and shaman tanks carry a shield, so a two-handed or off-hand weapon is no use to them (druid
--   tanks have no shield, and can).
-- * No tank wears cloth (cloaks aside, which are cloth for everyone).
-- * Armor lighter than a class tanks in counts for less the further below it is (TANK_ARMOR_STEP a type): leather
--   costs a shaman tank a little and a warrior or paladin tank more, without shutting them out of a fine piece.
local SHIELD_TANKS = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local NOT_WITH_SHIELD = { INVTYPE_2HWEAPON = true, INVTYPE_WEAPONOFFHAND = true }
local TANK_ARMOR = { WARRIOR = ARMOR.plate, PALADIN = ARMOR.plate, SHAMAN = ARMOR.mail, DRUID = ARMOR.leather }
local TANK_ARMOR_STEP = 0.25
local function TankShare(class, itemClass, subclass, equipLoc)
	if SHIELD_TANKS[class] and NOT_WITH_SHIELD[equipLoc] then return 0 end
	if itemClass ~= ITEM_ARMOR or equipLoc == "INVTYPE_CLOAK" then return 1 end
	if subclass == ARMOR.cloth then return 0 end
	local top = TANK_ARMOR[class]
	if not top or not subclass or subclass < ARMOR.leather or subclass > ARMOR.plate then return 1 end
	return math.max(1 - TANK_ARMOR_STEP * math.max(top - subclass, 0), 0)
end

local function Want(stat, role, class)
	local special = CLASS_WANTS[stat] and CLASS_WANTS[stat][class]
	if type(special) == "number" then return special end
	if special then return special[role] or 0 end
	return WANTS[stat][ROLE_INDEX[role]]
end

-- Whether a stat makes a role better at its job, so the item can be that role's at all: a damage item has to add to
-- damage and a healer item to healing, which stamina doesn't. Resistances have their own rule.
local function Helps(stat, role, class)
	if stat == "resistance" or ((stat == "sta" or stat == "hp5") and role ~= "TANK") then return false end
	return Want(stat, role, class) > 0
end

local KEEP = 0.8 -- roles within this share of the best fit count too
local CLASS_BAR = 0.6 -- a class whose best fit is at least this can need-roll on the item
local CLASS_KEEP = 0.75 -- or, for an item even its own classes fit less well, within this share of the best of them
local RESISTANCE_SHARE = 0.5 -- an item with this much of its budget in resistances is for everyone
local SIDE_SHARE = 1 / 3 -- spell damage's healing, or healing's damage, at no more than this of the other is left out

-- An item's stats, as the stats above, from its link; nil if the client hasn't loaded it yet.
local function ItemStats(link)
	local raw = link and C_Item.GetItemStats(link)
	if not raw then return nil end
	local stats = {}
	for key, value in pairs(raw) do
		local stat = STAT_KEYS[key]
		if stat and type(value) == "number" then
			stats[stat] = SUMMED[stat] and (stats[stat] or 0) + value or math.max(stats[stat] or 0, value)
		end
	end
	local dps = raw[WEAPON_DPS]
	if type(dps) == "number" then
		local _, _, _, _, _, itemClass, subclass = C_Item.GetItemInfoInstant(link)
		if itemClass == ITEM_WEAPON and subclass ~= WAND then stats[RANGED[subclass] and "rangedWeapon" or "weapon"] = dps end
	end
	-- Damage with a third as much healing, or the other way round: the smaller is left out. Otherwise what they share
	-- is spell power, damage and healing alike.
	local damage, healing = stats.damage or 0, stats.healing or 0
	if damage > 0 and healing > 0 then
		if healing <= damage * SIDE_SHARE + 1 then
			stats.healing = nil
		elseif damage <= healing * SIDE_SHARE + 1 then
			stats.damage = nil
		else
			local both = math.min(damage, healing)
			stats.spellPower = (stats.spellPower or 0) + both
			stats.damage = damage > both and damage - both or nil
			stats.healing = healing > both and healing - both or nil
		end
	end
	return stats
end

-- What a class's role wants of some stats, against the budget it could have wanted: weapon damage the role gets
-- nothing from isn't part of what's on offer to it. A tank wants only `tankShare` of it (TankShare).
local function Score(stats, class, role, tankShare)
	local wanted, offered, share = 0, 0, role == "TANK" and tankShare or 1
	for stat, value in pairs(stats) do
		local cost, want = value * COST[stat], share * Want(stat, role, class)
		wanted = wanted + cost * want
		if want > 0 or (stat ~= "weapon" and stat ~= "rangedWeapon") then offered = offered + cost end
	end
	return wanted, offered
end

local PLAYER_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- What an item's stats say: `roles`, the set of roles it's for (nil for all of them), and `classBest`, each class's best
-- fit, for the classes it does anything for (nil if it's everyone's: mostly resistances, or no stats these rules know).
-- False if its stats haven't loaded yet.
local analysed = {}
local function Analyse(item)
	if analysed[item] ~= nil then return analysed[item] end
	local _, link = C_Item.GetItemInfo(item)
	local stats = ItemStats(link)
	if not stats then return false end
	local budget, resistance = 0, (stats.resistance or 0) * COST.resistance
	for stat, value in pairs(stats) do budget = budget + value * COST[stat] end
	local result = {}
	if budget > 0 and resistance < RESISTANCE_SHARE * budget then
		local allowed, fits, classBest, best = ClassesAllowed(item), {}, {}, 0
		local _, _, _, equipLoc, _, itemClass, subclass = C_Item.GetItemInfoInstant(item)
		for _, class in ipairs(PLAYER_CLASSES) do
			if (not allowed or allowed[class]) and CanEquip(class, item) then
				local tankShare = TankShare(class, itemClass, subclass, equipLoc)
				for role in pairs(ns.CLASS_ROLES[class]) do
					local helps = role ~= "TANK" or tankShare > 0
					local any = false
					for stat in pairs(stats) do any = any or Helps(stat, role, class) end
					helps = helps and any
					local wanted, offered = Score(stats, class, role, tankShare)
					if helps and offered > 0 then
						local fit = wanted / offered
						fits[#fits + 1] = { role = role, fit = fit }
						classBest[class] = math.max(classBest[class] or 0, fit)
						best = math.max(best, fit)
					end
				end
			end
		end
		if best > 0 then
			result.roles, result.classBest = {}, classBest
			for _, entry in ipairs(fits) do
				if entry.fit >= KEEP * best then result.roles[entry.role] = true end
			end
		end
	end
	if C_Item.GetItemInfo(item) then analysed[item] = result end
	return result
end

local function SuggestedRoles(item)
	local result = Analyse(item)
	return result and result.roles
end

-- Each class's best fit on an item, and the roles it's for, for the stats probe (TestCommands.lua): nil while its
-- stats haven't loaded or if it's everyone's.
function ns.ItemFits(item)
	local result = Analyse(item)
	return result and result.classBest, result and result.roles
end

-- The classes in the group (made-up raiders too), cached until it changes.
local present
ns.Listen("ROSTER_CHANGED", function() present = nil end)
local function PresentClasses()
	if not present then
		present = {}
		for _, member in ipairs(ns.GroupMembers()) do
			if member.class then present[member.class] = true end
		end
	end
	return present
end

-- The fit a class needs to need-roll on an item (4.5): CLASS_BAR, the same whoever else is in the raid, as how much a
-- mage gets from an item has nothing to do with how much a druid does. An item whose own classes fit it less well (its
-- budget thinned by stats nobody much wants, like a healer's shield with as much stamina as healing) is measured
-- against them instead: within CLASS_KEEP of its best fit. Nil for items that are everyone's, or not loaded yet.
local function Bar(item)
	local result = Analyse(item)
	if not (result and result.classBest) then return nil end
	local best = 0
	for _, fit in pairs(result.classBest) do best = math.max(best, fit) end
	return math.min(CLASS_BAR, CLASS_KEEP * best), result.classBest
end

-- Whether a class gets enough from an item's stats to need-roll on it: a class that can wear or wield it but wants
-- little of what it offers (a rogue and a healer's dagger) can't. True while the item's stats haven't loaded, and for
-- items that are everyone's.
function ns.ItemSuitsClass(item, class)
	local bar, fits = Bar(item)
	if not bar then return true end
	return (fits[class] or 0) >= bar
end

-- Whether anyone in the group (or of `classes`, a set) can need-roll on an item. If not (a healer's plate in a raid
-- with no paladin), its roll is a greed roll straight away (4.5).
function ns.NeedViable(item, classes)
	local bar, fits = Bar(item)
	if not bar then return true end
	for class in pairs(classes or PresentClasses()) do
		if (fits[class] or 0) >= bar then return true end
	end
	return false
end

-- How well a unit's equipped gear suits each of the roles in `roles` (a set): the share of its whole budget each wants,
-- for the unit's class (4.6, roles from talents and gear). Nil if none of it could be read, and true as a second value
-- if some items haven't loaded yet (asked for, so a later look can read them).
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 } -- head to ranged, without shirt and tabard
function ns.GearFits(unit, class, roles)
	local wanted, offered, read, loading = {}, {}, false, false
	for _, slot in ipairs(GEAR_SLOTS) do
		local link = GetInventoryItemLink(unit, slot)
		if link then
			local stats = C_Item.GetItemInfo(link) and ItemStats(link)
			if stats then
				read = true
				local _, _, _, equipLoc, _, itemClass, subclass = C_Item.GetItemInfoInstant(link)
				local tankShare = TankShare(class, itemClass, subclass, equipLoc)
				for role in pairs(roles) do
					local w, o = Score(stats, class, role, tankShare)
					wanted[role], offered[role] = (wanted[role] or 0) + w, (offered[role] or 0) + o
				end
			else
				loading = true
				local item = ns.ItemID(link)
				if item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(item) end
			end
		end
	end
	if not read then return nil, loading end
	local fits = {}
	for role in pairs(roles) do fits[role] = (offered[role] or 0) > 0 and wanted[role] / offered[role] or 0 end
	return fits, loading
end

-- The roles an item is for, as a set, or nil for any role: an officer's say, kept in the ledger's item table
-- as role bits, or else what its stats suggest. Items that aren't gear, or whose stats say nothing, suit any role.
function ns.ItemRoles(item)
	if ns.ForEveryone(item) then return nil end
	local bits = ns.ledger and ns.ledger:ItemRoles(item)
	local suits
	if bits then
		suits = {}
		for role, bit in pairs(ns.ROLE_BITS) do
			if bits % (bit * 2) >= bit then suits[role] = true end
		end
	else
		suits = SuggestedRoles(item)
	end
	if not suits or next(suits) == nil then return nil end
	for _, role in ipairs(ns.ROLE_ORDER) do
		if not suits[role] then return suits end
	end
	return nil
end

-- Whether the item is off-spec for the player, true or false (nil if they aren't in the group), and whether that's
-- only by the fallback for a role that's unknown.
function ns.IsOffSpec(guid, item)
	local role, guessed = ns.RoleOf(guid)
	if not role then return nil end
	local suits = ns.ItemRoles(item)
	if not suits then return false, guessed end
	return not suits[role], guessed
end
