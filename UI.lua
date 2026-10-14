local _, ns = ...
local L = ns.L

-- The window, made from Forever's own templates and art so it sits alongside the game's panels: a portrait frame
-- with side tabs like the group finder, a stone header and list rows like its Who list, and the timer bar and
-- checkmark from the loot history. It shows the roll in progress (5.2), the master looter's loot, and your pity.

local WIDTH, HEIGHT = 384, 524
local ROW_HEIGHT = 52
local VALUE_WIDTH = 104 -- room on the right of a row you can roll or pass from, for its value and the pass button
local VALUE_INSET = 12 -- the value and note, from the row's right edge
local VALUE_GAP = 10 -- between a row's text and the value or note beside it
local TEXT_MARGIN = 6 -- a row's text, from its right edge when nothing's beside it
local DIVIDER_HEIGHT = 14
local DETAIL_COLUMNS = 3 -- a roll row's details: its roll, pity and off-spec, each in a column of the same width
-- Sized to their text ("Rerolled 62", "Pity +50", "Off-spec -20"), so the gaps between them look the same.
local COLUMN_WIDTHS = { 66, 54, 84 }
local COLUMN_OFFSETS = { 0, 66, 120 }
local ROW_WIDTH = WIDTH - 38 -- the list's width, inside its margins and scroll bar
local MIN_HEIGHT, MAX_HEIGHT = 400, 900
local BACKGROUND_FOCUS = 0.6 -- how far across the background art its crop centres
local ADDON_ICON = "Interface\\Icons\\INV_Misc_Dice_02"
local VIEWS = {
	{ key = "session", label = L.TAB_ROLL, icon = "Interface\\Icons\\INV_Misc_Dice_02" },
	{ key = "pity", label = L.TAB_PITY, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
	{ key = "loot", label = L.TAB_LOOT, icon = "Interface\\Icons\\INV_Box_02" }, -- only there once loot has been seen
	{ key = "raid", label = L.TAB_RAID, icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend" }, -- see ns.ShowsRaidTab
	{ key = "options", label = L.TAB_OPTIONS, icon = "Interface\\Icons\\INV_Misc_Gear_01" }, -- always at the bottom
}
local EMPTY = {
	session = L.EMPTY_SESSION,
	pity = L.EMPTY_PITY,
	loot = L.EMPTY_LOOT,
	options = "",
	raid = L.EMPTY_RAID,
}
local STATES = {
	open = L.STATE_OPEN, reroll = L.STATE_REROLL, decided = L.STATE_DECIDED, cancelled = L.STATE_CANCELLED,
	awarded = L.STATE_AWARDED, disenchanted = L.STATE_DISENCHANTED, kept = L.STATE_KEPT,
}
local GREY = { r = 0.486, g = 0.518, b = 0.541 } -- FRIENDS_GRAY_COLOR, which the Who list uses for its details
local HEADER_HEIGHT = 26
local OTHER_RAID = L.PITY_OTHER_RAID -- items with no recorded raid, such as ones set by hand
local OTHER_BOSS = L.PITY_UNKNOWN_BOSS
local WARNINGS_SHOWN = 5
local TRADES = "trades" -- the Loot tab's group of won items awaiting trade
local TRADE_WARNING = 30 * 60 -- seconds left to trade an item below which its time shows in red
local PASS_SIZE = 24
local TRADE_REFRESH = 5 -- seconds between redraws of the time left to trade items
local FOOTER_LEFT, FOOTER_MIDDLE = 14, 23 -- where the footer's text starts, and the height of its middle
local BUTTON_MARGIN, PRIMARY_WIDTH, CANCEL_WIDTH = 10, 110, 88

local frame
local view = "session"
local lines = {}
-- A roll whose off-spec flag the writer just flipped keeps its place in the list while the mouse is on it, rather than
-- jumping out from under the cursor as its total changes: { id, index, sid }.
local held

local function Colored(text, color)
	if not color then return text end
	return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, text)
end

-- What the window offers: writer and officer controls, unless test mode is showing it as a raider sees it.
local function AsWriter()
	return ns.AmWriter() and not ns.ViewAsRaider()
end

local function AsOfficer()
	return ns.IsOfficer(ns.PlayerName()) and not ns.ViewAsRaider()
end

-- The Raid tab is always there for officers; members can show it with an option, to look at.
function ns.ShowsRaidTab()
	return AsOfficer() or ns.settings.showRaidTab == true
end

local function NameList(ids)
	local names = {}
	for i, id in ipairs(ids) do names[i] = ns.ColoredName(id) end
	return table.concat(names, ", ")
end

-- Everyone in a pool can win (no bonus is 100 above another's), so a chance too small to show is shown as 0.1%.
local function Percent(chance)
	if chance < 0.001 then return "0.1%" end
	if chance >= 0.995 then return ("%d%%"):format(chance * 100 + 0.5) end
	return ("%.1f%%"):format(chance * 100)
end

local function ItemIcon(item)
	return (select(10, C_Item.GetItemInfo(item)))
end

-- How wide a font string's text is, however much room it's been given.
-- An item's link without the brackets round its name, as the Loot and My Pity tabs and the window's header show it:
-- still in its quality's colour, and still a link.
local function ItemText(item)
	return (ns.ItemLink(item):gsub("|h%[(.-)%]|h", "|h%1|h"))
end

-- The colour an item's icon is framed in, as the game's item buttons do it: none for qualities without one.
local function QualityColor(item)
	local quality = select(3, C_Item.GetItemInfo(item))
	if not quality then return nil end
	if ColorManager and ColorManager.GetColorDataForBagItemQuality then
		return ColorManager.GetColorDataForBagItemQuality(quality)
	end
	return quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] or nil
end

local function TextWidth(fontString)
	local width = fontString.GetUnboundedStringWidth and fontString:GetUnboundedStringWidth() or fontString:GetStringWidth()
	return tonumber(width) or 0
end

-- Lines for each view. `cells` are the bare values; the rest is how a row shows them.

-- Why you can't take part in a roll (ns.WhyCantRoll), on your row and in its tooltip.
local CANT_ROLL = {
	nottied = { L.CANT_ROLL_NOT_TIED, L.CANT_ROLL_NOT_TIED_TIP },
	won = { L.CANT_ROLL_WON, L.CANT_ROLL_WON_TIP },
	class = { L.CANT_ROLL_CLASS, L.CANT_ROLL_CLASS_TIP },
}

-- A /roll of yours the writer didn't count, on your own row the same way, saying why: in place of its details when
-- no roll of yours counts (after a wrong range you can still roll, so the row still rolls), or in its tooltip when
-- one does.
local function ShowRefusal(out)
	local refusal = ns.MyRefusal()
	if not refusal then return end
	local me = UnitGUID("player")
	local reason = refusal.why == "range" and L.WHY_RANGE:format(refusal.low or 0, refusal.high or 0)
		or L["WHY_" .. refusal.why:upper()]
	local sentence = L.REFUSED:format(refusal.roll, reason)
	local line
	for _, each in ipairs(out) do
		if each.mine then
			line = each
			break
		end
	end
	if line and line.counted then
		line.tip[#line.tip + 1] = sentence
		return
	end
	if not line then
		line = {
			mine = true,
			cells = { name = ns.NameOf(me), pity = "", spec = "", roll = "-", total = "", odds = "" },
			title = ns.ColoredName(me),
			faded = true,
		}
		table.insert(out, 1, line)
	end
	line.columns, line.detail = nil, L.REFUSED_DETAIL:format(reason)
	if line.prompt then
		line.tip = { L.ROLL_TIP_TITLE, sentence, refusal.why == "range" and L.REFUSED_RANGE_ONLY or nil }
		line.hints = refusal.why == "range" and { L.REFUSED_RANGE_HINT } or nil
	else
		line.tip = { ns.ColoredName(me), sentence }
	end
end

local function SessionLines()
	local m = ns.live.mirror
	local out = {}
	if not m then return out end
	local canFlip = AsWriter() and m.state == "open" and not m.greed and not ns.ForEveryone(m.item)
	local rolledAbove, divided = false, false
	for _, row in ipairs(ns.SessionRows()) do
		local id = row.id
		local spec = ""
		if row.roll then spec = row.offSpec and "off" or (row.unknownRole and "?" or "main") end
		local columns = {
			row.roll and (row.round > 1 and L.ROW_REROLLED or L.ROW_ROLLED):format(row.roll) or "",
			row.pity and row.pity > 0 and L.ROW_PITY:format(row.pity) or "",
			-- A penalty from a fallback role, while theirs is unknown, has a question mark.
			row.offSpec and (row.unknownRole and L.ROW_OFFSPEC_GUESSED or L.ROW_OFFSPEC):format(ns.OFFSPEC_MODIFIER)
				or (row.unknownRole and L.ROW_ROLE_UNKNOWN) or "",
		}
		-- The roll and what went into it; the total is the number being hovered.
		local waiting = m.state == "reroll" and row.contender and L.ROW_NOT_REROLLED or L.ROW_NOT_ROLLED
		local summary = { row.roll and tostring(row.roll) or (row.passed and L.ROW_PASSED) or waiting }
		if row.roll and row.pity and row.pity > 0 then summary[#summary + 1] = "+" .. row.pity end
		if row.roll and row.offSpec then summary[#summary + 1] = L.ROW_TIP_OFFSPEC:format(ns.OFFSPEC_MODIFIER) end
		local tip = { ns.ColoredName(id, row.name), table.concat(summary, " ") }
		if row.stale then tip = { tip[1], L.ROW_TIP_BEFORE_TIE:format(tip[2]), waiting } end
		-- The writer left-clicks a roll to flip its off-spec flag, which the tooltip's click hint says.
		local hints = canFlip and row.roll and { row.offSpec and L.HINT_COUNT_MAIN or L.HINT_COUNT_OFF } or nil
		local click = canFlip and row.roll and function(button)
			if button ~= "LeftButton" then return end
			for i, line in ipairs(lines) do
				if line.playerId == id then held = { id = id, index = i, sid = m.sid } end
			end
			ns.ToggleOffSpec(id)
		end or nil
		local mine = id == UnitGUID("player")
		local prompt
		if row.prompt then
			tip, hints = { L.ROLL_TIP_TITLE, L.ROLL_TIP }, nil
			click = ns.Roll
			prompt = m.state == "reroll" and L.PROMPT_REROLL or L.PROMPT_ROLL
			if row.autoRollAt then prompt = L.PROMPT_AUTO_ROLL:format(math.max(math.ceil(row.autoRollAt - GetTime()), 1)) end
		elseif mine and row.passed then
			tip[2] = L.ROW_TIP_PASSED
		end
		-- Your chance of winning goes under the roll (until you've rolled, there's no roll above it). A roll from before
		-- a tie stays until its player rerolls, greyed out.
		local note = ""
		if row.passed then
			note = L.ROW_PASSED
		elseif row.odds then
			note = L.ROW_CHANCE:format(Percent(row.odds))
		elseif (not row.roll or row.stale) and not (row.prompt or row.rolling) then
			note = waiting
		end
		-- In a reroll, a divider between the tied players, who come first, and everyone else.
		if m.contenders and not row.contender and out[1] and out[#out].contender then
			out[#out + 1] = { divider = true }
		end
		-- Otherwise, one between those who've rolled and those who haven't (or passed), when there are both; your own
		-- row at the top while you can roll stays above them.
		local pinned = row.prompt or row.rolling
		if not m.contenders and not pinned and not row.roll and rolledAbove and not divided then
			out[#out + 1] = { divider = true }
			divided = true
		end
		if row.roll and not pinned then rolledAbove = true end
		out[#out + 1] = {
			mine = mine,
			mineColor = mine and RAID_CLASS_COLORS[ns.ClassOf(id) or ""] or nil,
			cells = {
				name = row.name, pity = row.pity and ("+" .. row.pity) or "", spec = spec,
				roll = row.roll and tostring(row.roll) or "-", total = row.total and tostring(row.total) or "",
				odds = row.odds and Percent(row.odds) or "",
			},
			title = ns.ColoredName(id, row.name),
			columns = columns,
			value = row.total and tostring(row.total) or "",
			valueColor = row.stale and GREY or nil,
			note = note,
			prompt = prompt,
			pass = row.prompt and m.state ~= "reroll" and ns.Pass or nil, -- not in a reroll, where the earlier roll is
			passTip = m.state == "reroll" and L.PASS_TIP_REROLL or L.PASS_TIP_ROLL,
			winner = row.winner,
			contender = row.contender,
			counted = mine and row.roll ~= nil and not row.stale or nil, -- your own row, with a roll that counts
			faded = ((not row.roll or row.stale) and not (row.prompt or row.rolling)) or row.passed,
			tip = tip,
			hints = hints,
			click = click,
			playerId = id,
		}
	end
	-- A roll you can't take part in is still shown, with your own row saying why, so you can follow it: at the top, or
	-- in a reroll you're not in, at the top of everyone else's, below the tied players.
	local why = ns.WhyCantRoll()
	local me = UnitGUID("player")
	local listed = false
	for _, line in ipairs(out) do
		if line.mine then listed = true end
	end
	if why and not listed then
		local at = 1
		if m.contenders then
			while out[at] and out[at].contender do at = at + 1 end
			if at > 1 then
				if not (out[at] and out[at].divider) then table.insert(out, at, { divider = true }) end
				at = at + 1
			end
		end
		table.insert(out, at, {
			mine = true,
			cells = { name = ns.NameOf(me), pity = "", spec = "", roll = "-", total = "", odds = "" },
			title = ns.ColoredName(me),
			detail = CANT_ROLL[why][1],
			faded = true,
			tip = { ns.ColoredName(me), CANT_ROLL[why][2] },
		})
	end
	ShowRefusal(out)
	-- A roll the writer just flipped stays where it was, under the mouse (the window lets it go once the mouse is off).
	if held and held.sid == m.sid then
		for i, line in ipairs(out) do
			if line.playerId == held.id and i ~= held.index then
				table.remove(out, i)
				table.insert(out, math.min(held.index, #out + 1), line)
				break
			end
		end
	end
	return out
end

-- Each boss's loot, for everyone, under a header per boss in the order it was seen. Each item shows how its roll went
-- and your pity on it; awarded ones are greyed out with their winners. Only the writer gets buttons to start rolls.
local lootCollapsed = {}

-- "1h 42m", "28m", or "Expired".
local function TimeLeft(seconds)
	if seconds <= 0 then return L.TRADE_EXPIRED end
	local minutes = math.ceil(seconds / 60)
	if minutes < 60 then return L.TIME_MINUTES:format(minutes) end
	return L.TIME_HOURS:format(math.floor(minutes / 60), minutes % 60)
end

-- Won items not yet handed over, one row per copy, at the top of the Loot tab: all of them for officers, and your
-- own for you. Each shows how long is left to trade it, in red once it's under half an hour. An officer holding a
-- copy left-clicks it to open a trade with the winner, which puts it in.
local function TradeLines(out)
	local me, officer = UnitGUID("player"), AsOfficer()
	local now = GetServerTime()
	local rows = {}
	for _, pending in ipairs(ns.PendingTrades()) do
		if officer or pending.id == me then
			local left = pending.expires - now
			local detail = {}
			if pending.id ~= me then detail[#detail + 1] = L.TRADE_FOR:format(ns.ColoredName(pending.id)) end
			if pending.from and not ns.IsMe(pending.from) then detail[#detail + 1] = L.TRADE_FROM:format(ns.ColoredName(pending.from)) end
			local click, hints
			if officer then
				-- In test mode the loot isn't really in your bags, so it's traded as if it were.
				local canTrade = left > 0 and pending.id ~= me and (ns.HoldsItem(pending.item) or ns.IsTestMode())
				hints = {}
				if canTrade then hints[1] = L.HINT_TRADE:format(ns.ColoredName(pending.id)) end
				hints[#hints + 1] = left > 0 and L.HINT_TRADE_DONE or L.HINT_TRADE_CLEAR
				click = function(button)
					if button == "RightButton" then
						ns.MarkTraded(pending.sid, pending.id)
					elseif canTrade then
						ns.OfferTrade(pending.id)
					end
				end
			end
			rows[#rows + 1] = {
				cells = { name = ItemText(pending.item), pity = "", spec = "trade" },
				icon = ItemIcon(pending.item),
				title = ItemText(pending.item),
				detail = table.concat(detail, "  ·  "),
				value = TimeLeft(left),
				valueColor = left < TRADE_WARNING and RED_FONT_COLOR or nil,
				note = left > 0 and L.TRADE_NOTE or nil,
				mine = pending.id == me,
				item = pending.item,
				click = click,
				hints = hints,
			}
		end
	end
	if not rows[1] then return end
	out[#out + 1] = {
		header = 1, key = TRADES, collapsed = lootCollapsed[TRADES], text = L.TRADE_HEADER:format(#rows),
		toggle = function() lootCollapsed[TRADES] = not lootCollapsed[TRADES] or nil end,
	}
	if lootCollapsed[TRADES] then return end
	for _, row in ipairs(rows) do out[#out + 1] = row end
end

-- The game's icon for a role: the borderless ones Forever's group finder shows for players listed on their own, not
-- the circled ones it shows for groups.
local ROLE_ICONS = {
	TANK = "groupfinder-icon-role-micro-tank", HEALER = "groupfinder-icon-role-micro-heal", DAMAGER = "groupfinder-icon-role-micro-dps",
}
local ROLE_ICON_SIZE = 16
-- The icons' art has a margin of its own, so they sit closer together, and to the text, than their size suggests;
-- and a little lower than the middle of the text, level with its letters.
local ROLE_ICON_STEP, ROLE_ICON_INSET, ROLE_ICON_GAP, ROLE_ICON_DROP = ROLE_ICON_SIZE - 2, -2, 1, 1
local function RoleIcon(role)
	return CreateAtlasMarkup(ROLE_ICONS[role], ROLE_ICON_SIZE, ROLE_ICON_SIZE)
end

-- The roles in a set, in the usual order.
local function RoleList(suits)
	local list = {}
	for _, role in ipairs(ns.ROLE_ORDER) do
		if suits[role] then list[#list + 1] = role end
	end
	return list
end

-- An officer's menu for an item, from a right-click: a greed roll, if the writer can start one, and the item's roles
-- (4.6), ticked as they stand. Changing them is recorded in the ledger for everyone.
local function ShowItemMenu(owner, item, greedRoll)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(C_Item.GetItemInfo(item) or ns.ItemLink(item))
		if greedRoll then root:CreateButton(L.MENU_GREED_ROLL, greedRoll) end
		root:CreateTitle(L.MENU_ROLES)
		for _, role in ipairs(ns.ROLE_ORDER) do
			local function Suits()
				local suits = ns.ItemRoles(item)
				return suits == nil or suits[role] == true
			end
			root:CreateCheckbox(RoleIcon(role) .. " " .. ns.ROLE_NAMES[role], Suits, function()
				local suits = {}
				for _, other in ipairs(ns.ROLE_ORDER) do
					local current = ns.ItemRoles(item)
					suits[other] = (current == nil or current[other]) or nil
				end
				suits[role] = not Suits() or nil
				ns.SetItemRoles(item, suits)
			end)
		end
	end)
end

local function Contains(ids, id)
	for _, each in ipairs(ids or {}) do
		if each == id then return true end
	end
	return false
end

-- The group's items you see: all of them, unless you hide loot you can't roll on (the writer sees everything). The
-- copy you win stays; it's later drops of an item you've won that are hidden. Anyone can greed-roll a BoE, so those
-- always show.
local function ShownItems(group)
	if not ns.settings.hideUnrollable or AsWriter() then return group.items end
	local me, shown = UnitGUID("player"), {}
	for _, entry in ipairs(group.items) do
		if entry.boe or ns.MayRollOn(me, entry.item) or Contains(entry.winners, me) or Contains(entry.pending, me) then
			shown[#shown + 1] = entry
		end
	end
	return shown
end

local function LootLines()
	local out = {}
	TradeLines(out)
	local canStart = AsWriter()
	local me = UnitGUID("player")
	for index, group in ipairs(ns.loot.groups) do
		local key = group.key
		local items = ShownItems(group)
		if items[1] then
			out[#out + 1] = {
				header = 1, key = key, collapsed = lootCollapsed[key],
				text = ("%s (%d)"):format(group.boss or L.LOOT_GROUP:format(index), #items),
				toggle = function() lootCollapsed[key] = not lootCollapsed[key] or nil end,
			}
		end
		for _, entry in ipairs(lootCollapsed[key] and {} or items) do
			local item = entry.item
			local done = ns.LootDone(entry)
			local detail = {}
			-- Once it's won, the winners show how many there were.
			if entry.copies > 1 and not done and entry.status ~= "decided" then detail[#detail + 1] = L.LOOT_COPIES:format(entry.copies) end
			if entry.boe then detail[#detail + 1] = L.LOOT_BOE end
			-- The icons of the roles it's for, unless it's for any of them, start the details.
			local suits = not done and ns.ItemRoles(item)
			local status
			if entry.status == "rolling" then
				status = Colored(L.LOOT_ROLLING, NORMAL_FONT_COLOR)
			elseif entry.status == "decided" then
				status = L.LOOT_WON_BY:format(NameList(entry.pending or {}))
			elseif entry.status == "disenchanted" or entry.status == "kept" then
				local kept = entry.status == "kept"
				if entry.winners[1] then
					status = (kept and L.LOOT_AWARDED_REST_KEPT or L.LOOT_AWARDED_REST_DISENCHANTED):format(NameList(entry.winners))
				else
					status = kept and L.STATE_KEPT or L.STATE_DISENCHANTED
				end
			elseif done then
				status = L.LOOT_AWARDED_TO:format(NameList(entry.winners))
			elseif entry.winners[1] then
				status = L.LOOT_PART_AWARDED:format(#entry.winners, entry.copies, NameList(entry.winners))
			elseif entry.status == "none" then
				status = L.LOOT_NO_ONE_ROLLED
			end
			if status then detail[#detail + 1] = status end
			-- The writer starts rolls with a left-click; a right-click is a BoE's greed roll, and for officers, a menu
			-- with that and the item's roles.
			local click, hints
			local canRoll = canStart and (entry.status == "waiting" or entry.status == "none")
			local copies = entry.copies - #entry.winners
			local greed = canRoll and entry.boe and function() ns.StartRoll(item, copies, true) end or nil
			local setRoles = AsOfficer() and not ns.ForEveryone(item)
			if canRoll or greed or setRoles then
				hints = {}
				if canRoll then hints[#hints + 1] = L.HINT_START_ROLL end
				if greed and setRoles then
					hints[#hints + 1] = L.HINT_GREED_OR_ROLES
				elseif greed then
					hints[#hints + 1] = L.HINT_GREED
				elseif setRoles then
					hints[#hints + 1] = L.HINT_SET_ROLES
				end
				click = function(button, owner)
					if button == "LeftButton" and canRoll then
						ns.StartRoll(item, copies)
					elseif button == "RightButton" and setRoles then
						ShowItemMenu(owner, item, greed)
					elseif button == "RightButton" and greed then
						greed()
					end
				end
			end
			-- Your own pity on it, on the right, if you have any.
			local won = ns.HasWon(me, item)
			local pity = ns.PityOf(me, item)
			local value, note = "", nil
			if won then
				note = L.LOOT_WON_NOTE
			elseif pity > 0 then
				value, note = "+" .. pity, L.LOOT_PITY_NOTE
			end
			local name = C_Item.GetItemInfo(item)
			out[#out + 1] = {
				cells = { name = ItemText(item), pity = "x" .. entry.copies, spec = entry.status },
				icon = ItemIcon(item),
				title = done and Colored(name or ItemText(item), GREY) or ItemText(item),
				detail = table.concat(detail, "  ·  "),
				roles = suits and RoleList(suits) or nil,
				value = value,
				note = note,
				contender = entry.status == "rolling",
				faded = done,
				desaturate = done,
				item = item,
				click = click,
				hints = hints,
			}
		end
	end
	return out
end

-- Sorted names, with the catch-all group last.
local function SortedKeys(groups, last)
	local keys = {}
	for key in pairs(groups) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b)
		if (a == last) ~= (b == last) then return b == last end
		return a < b
	end)
	return keys
end

-- Entering a raid opens its group on My pity, bosses and all, and folds every other raid away, the next time the
-- list is drawn. After that the groups stay as you leave them until you enter a raid again.
local focusRaid, inRaid

ns.On("PLAYER_ENTERING_WORLD", function()
	local name, instanceType = GetInstanceInfo()
	local raid = instanceType == "raid" and name or nil
	if raid and raid ~= inRaid then focusRaid = raid end
	inRaid = raid
end)

local function FocusRaid(raids)
	local collapsed = ns.saved.collapsed
	for raid, group in pairs(raids) do
		collapsed[raid] = raid ~= focusRaid or nil
		if raid == focusRaid then
			for boss in pairs(group.bosses) do collapsed[raid .. " / " .. boss] = nil end
		end
	end
	focusRaid = nil
end

-- Your pity, grouped under the raid each item drops in, and optionally the boss, as collapsible headers like the
-- currency list's. Items with the most pity come first; items already won come last.
local function PityLines()
	local out = {}
	local me = UnitGUID("player")
	if not ns.ledger then return out end
	local byBoss = ns.settings.pityByBoss
	local raids = {}
	local function Add(item, pity, note, won)
		-- Where it drops, from the item table: a raid's trash goes under Unknown boss, and the raidless catch-all is Other.
		local raidName, bossName = ns.ledger:Source(item)
		local raid = raidName and raidName ~= "" and raidName or OTHER_RAID
		local boss = byBoss and (bossName and bossName ~= "" and bossName or OTHER_BOSS) or ""
		raids[raid] = raids[raid] or { count = 0, bosses = {} }
		raids[raid].count = raids[raid].count + 1
		raids[raid].bosses[boss] = raids[raid].bosses[boss] or {}
		local chance = pity and pity > 0 and ns.HeadToHead(pity) or nil
		table.insert(raids[raid].bosses[boss], {
			cells = { name = ItemText(item), pity = pity and ("+" .. pity) or "", spec = note },
			icon = ItemIcon(item),
			title = ItemText(item),
			detail = note,
			value = pity and ("+" .. pity) or "",
			note = chance and L.PITY_ODDS:format(chance * 100 + 0.5) or nil,
			sort = pity or -1,
			winner = won,
			item = item,
		})
	end
	-- Pity that's decayed to nothing isn't pity any more.
	for _, sub in pairs(ns.RowsOf(me)) do
		for item, cell in pairs(sub.cells) do
			if cell == ns.CELL_WON then
				if not ns.settings.hideWon then Add(item, nil, L.PITY_WON, true) end
			else
				local pity = ns.PityOf(me, item)
				if pity > 0 then Add(item, pity) end
			end
		end
	end

	if focusRaid then FocusRaid(raids) end
	local collapsed = ns.saved.collapsed
	for _, raid in ipairs(SortedKeys(raids, OTHER_RAID)) do
		local group = raids[raid]
		out[#out + 1] = {
			header = 1, key = raid, text = ("%s (%d)"):format(raid, group.count), collapsed = collapsed[raid],
			toggle = function() collapsed[raid] = not collapsed[raid] or nil end,
		}
		if not collapsed[raid] then
			for _, boss in ipairs(SortedKeys(group.bosses, OTHER_BOSS)) do
				local key = raid .. " / " .. boss
				local items = group.bosses[boss]
				if byBoss then
					out[#out + 1] = {
						header = 2, key = key, text = ("%s (%d)"):format(boss, #items), collapsed = collapsed[key],
						toggle = function() collapsed[key] = not collapsed[key] or nil end,
					}
				end
				if not (byBoss and collapsed[key]) then
					table.sort(items, function(a, b)
						if a.sort ~= b.sort then return a.sort > b.sort end
						return a.item < b.item
					end)
					for _, line in ipairs(items) do out[#out + 1] = line end
				end
			end
		end
	end
	return out
end

-- Rows -----------------------------------------------------------------------------------------------------------

local function ShowTooltip(owner, line)
	if not line.item and not line.tip then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if line.item then
		-- Compared with what you're wearing only while Shift's held, whatever the game's Always Compare Items says.
		if GameTooltip_SuppressAutomaticCompareItem then GameTooltip_SuppressAutomaticCompareItem(GameTooltip) end
		GameTooltip:SetItemByID(line.item)
	else
		GameTooltip_SetTitle(GameTooltip, line.tip[1])
		for i = 2, #line.tip do GameTooltip_AddNormalLine(GameTooltip, line.tip[i]) end
	end
	for _, hint in ipairs(line.hints or {}) do ns.AddHint(GameTooltip, hint) end
	GameTooltip:Show()
end

local function BuildRow(row)
	row.built = true
	row:SetHeight(ROW_HEIGHT)
	row.Background = row:CreateTexture(nil, "BACKGROUND")
	row.Background:SetAtlas("common-button-list-large")
	row.Background:SetAllPoints()
	row.Selected = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.Selected:SetAtlas("common-button-list-large-selected")
	row.Selected:SetAllPoints()
	row:SetHighlightAtlas("common-button-list-large-hover", "ADD")
	-- Your own row keeps the hover glow, so it's easy to find.
	row.Mine = row:CreateTexture(nil, "BACKGROUND", nil, 2)
	row.Mine:SetAtlas("common-button-list-large-hover")
	row.Mine:SetAllPoints()
	row.Mine:SetBlendMode("ADD")
	row.Mine:SetAlpha(0.6)

	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(34, 34)
	row.Icon:SetPoint("LEFT", 9, 0)
	row.IconBorder = row:CreateTexture(nil, "OVERLAY")
	row.IconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
	row.IconBorder:SetAllPoints(row.Icon)
	row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalMed1")
	row.Title:SetJustifyH("LEFT")
	row.Title:SetWordWrap(false)
	row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Detail:SetJustifyH("LEFT")
	row.Detail:SetWordWrap(false)
	row.Detail:SetTextColor(GREY.r, GREY.g, GREY.b)
	row.RoleIcons = {}
	for i = 1, #ns.ROLE_ORDER do
		row.RoleIcons[i] = row:CreateTexture(nil, "ARTWORK")
		row.RoleIcons[i]:SetSize(ROLE_ICON_SIZE, ROLE_ICON_SIZE)
	end
	row.Columns = {}
	for i = 1, DETAIL_COLUMNS do
		local column = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		column:SetJustifyH("LEFT")
		column:SetWordWrap(false)
		column:SetTextColor(GREY.r, GREY.g, GREY.b)
		row.Columns[i] = column
	end
	-- The value on the top line, and a note on the bottom line, level with the details.
	row.Value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	row.Value:SetPoint("TOPRIGHT", -VALUE_INSET, -9)
	row.Note = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Note:SetPoint("BOTTOMRIGHT", -VALUE_INSET, 11)
	row.Note:SetTextColor(GREY.r, GREY.g, GREY.b)
	row.Check = row:CreateTexture(nil, "OVERLAY")
	row.Check:SetAtlas("lootroll-icon-checkmark", true)
	-- "Click to roll", across the middle of your own row while you can roll.
	row.Prompt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	-- Passing, with the group loot roll's own pass button, in the top right corner of your row: apart from the rest of
	-- the row, which rolls.
	row.Pass = CreateFrame("Button", nil, row)
	row.Pass:SetSize(PASS_SIZE, PASS_SIZE)
	row.Pass:RegisterForClicks("LeftButtonDown") -- as the row's own click, so a redraw can't lose it
	row.Pass:SetPoint("TOPRIGHT", -8, -5)
	row.Pass:SetNormalAtlas("lootroll-toast-icon-pass-up")
	row.Pass:SetHighlightAtlas("lootroll-toast-icon-pass-highlight", "ADD")
	row.Pass:SetPushedAtlas("lootroll-toast-icon-pass-down")
	row.Pass:SetScript("OnClick", function(self)
		local line = self:GetParent().line
		if line and line.pass then line.pass() end
	end)
	row.Pass:SetScript("OnEnter", function(self)
		local line = self:GetParent().line
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, PASS or "Pass")
		if line and line.passTip then GameTooltip_AddNormalLine(GameTooltip, line.passTip, true) end
		GameTooltip:Show()
	end)
	row.Pass:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- A left-click acts as the button goes down: the list redraws often during a roll, handing its rows out again,
	-- and a click that waited for the button to come back up was lost whenever that happened in between.
	row:RegisterForClicks("LeftButtonDown", "RightButtonUp")
	row:SetScript("OnClick", function(self, button) if self.line and self.line.click then self.line.click(button, self) end end)
	row:SetScript("OnEnter", function(self) if self.line then ShowTooltip(self, self.line) end end)
	-- The game redraws a hovered button's tooltip through this, as its own item buttons do, so Shift's comparisons
	-- show (and the tooltip stays) rather than the tooltip being rebuilt without us.
	row.UpdateTooltip = function(self) if self.line then ShowTooltip(self, self.line) end end
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function InitRow(row, line)
	if not row.built then BuildRow(row) end
	row.line = line
	local left = 12
	row.Icon:SetShown(line.icon ~= nil)
	if line.icon then
		row.Icon:SetTexture(line.icon)
		left = 50
	end
	local border = line.icon and line.item and QualityColor(line.item)
	row.IconBorder:SetShown(border ~= nil)
	if border then row.IconBorder:SetVertexColor(border.r, border.g, border.b) end
	-- The name runs up to the value beside it, and the details up to the note beside them, or else to the right
	-- edge; a row you can roll or pass from keeps room for those all along.
	row.Value:SetText(line.value or "")
	row.Note:SetText(line.note or "")
	local right, detailRight = -TEXT_MARGIN, -TEXT_MARGIN
	if line.prompt or line.pass then
		right, detailRight = -VALUE_WIDTH, -VALUE_WIDTH
	else
		local beside = (line.value or "") ~= "" and TextWidth(row.Value) or 0
		-- A winner's checkmark sits beside the value, or at the right edge.
		if line.winner then beside = beside + (beside > 0 and 4 or 0) + (tonumber(row.Check:GetWidth()) or 0) end
		if beside > 0 then right = -(VALUE_INSET + beside + VALUE_GAP) end
		if (line.note or "") ~= "" then detailRight = -(VALUE_INSET + TextWidth(row.Note) + VALUE_GAP) end
		-- Without a value, the checkmark is in the middle of the row's height, beside the details too.
		if line.winner and (line.value or "") == "" then detailRight = math.min(detailRight, right) end
	end
	row.Title:ClearAllPoints()
	row.Title:SetPoint("TOPLEFT", left, -9)
	row.Title:SetPoint("RIGHT", right, 0)
	row.Title:SetText(line.title)
	-- Role icons start the details. They're textures beside the text rather than in it, as they're taller than the
	-- text and would push its line down.
	local _, fontHeight = row.Detail:GetFont()
	local indent = 0
	for i, icon in ipairs(row.RoleIcons) do
		local role = line.roles and line.roles[i]
		icon:SetShown(role ~= nil)
		if role then
			icon:SetAtlas(ROLE_ICONS[role])
			icon:ClearAllPoints()
			icon:SetPoint("LEFT", row.Title, "BOTTOMLEFT", ROLE_ICON_INSET + indent,
				-6 - (tonumber(fontHeight) or 10) / 2 - ROLE_ICON_DROP)
			indent = indent + ROLE_ICON_STEP
		end
	end
	if indent > 0 then indent = indent + ROLE_ICON_INSET + (ROLE_ICON_SIZE - ROLE_ICON_STEP) + ROLE_ICON_GAP end
	row.Detail:ClearAllPoints()
	row.Detail:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", indent, -6)
	row.Detail:SetPoint("RIGHT", detailRight, 0)
	row.Detail:SetText(line.detail or "")
	row.Detail:SetShown(line.columns == nil)
	-- Columns the same width on every row, so the rolls, pity and off-spec line up down the list.
	local x = 0
	for i, column in ipairs(row.Columns) do
		column:ClearAllPoints()
		column:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", x, -6)
		column:SetWidth(COLUMN_WIDTHS[i] - 4)
		x = x + COLUMN_WIDTHS[i]
		column:SetText(line.columns and line.columns[i] or "")
		column:SetShown(line.columns ~= nil)
	end
	local valueColor = line.valueColor or line.mineColor or (line.contender and NORMAL_FONT_COLOR) or HIGHLIGHT_FONT_COLOR
	row.Value:SetTextColor(valueColor.r, valueColor.g, valueColor.b)
	row.Pass:SetShown(line.pass ~= nil)
	-- The checkmark sits beside the value, or in the middle of the right edge when there's no value.
	row.Check:ClearAllPoints()
	if (line.value or "") ~= "" then
		row.Check:SetPoint("RIGHT", row.Value, "LEFT", -4, 0)
	else
		row.Check:SetPoint("RIGHT", -VALUE_INSET, 0)
	end
	-- The prompt is centred on the row, unless that would run it into your name or details.
	row.Prompt:SetShown(line.prompt ~= nil)
	row.Prompt:SetText(line.prompt or "")
	if line.prompt then
		local used = TextWidth(row.Title)
		for i, column in ipairs(row.Columns) do
			if line.columns and (line.columns[i] or "") ~= "" then
				used = math.max(used, COLUMN_OFFSETS[i] + TextWidth(column))
			end
		end
		row.Prompt:ClearAllPoints()
		row.Prompt:SetPoint("LEFT", math.max((ROW_WIDTH - TextWidth(row.Prompt)) / 2, left + used + 16), 0)
	end
	row.Selected:SetShown(line.winner == true)
	row.Mine:SetShown(line.mine == true)
	row.Check:SetShown(line.winner == true)
	row.Icon:SetDesaturated(line.desaturate == true)
	row:SetAlpha(line.faded and 0.6 or 1)
end

-- The divider in a reroll, between the tied players and everyone else: the group finder's scroll line.
local function InitDivider(divider)
	if divider.built then return end
	divider.built = true
	local line = divider:CreateTexture(nil, "ARTWORK")
	line:SetAtlas("groupfinder-ScrollLine")
	line:SetPoint("LEFT", 4, 0)
	line:SetPoint("RIGHT", -4, 0)
	line:SetHeight(8)
end

-- Group headers, like the currency list's: a raid is a full-width bar with a plus or minus, a boss under it is
-- indented with the campaign header's arrow. Clicking either folds it away, and that's remembered.
local function BuildHeader(header)
	header.built = true
	header.Bar = header:CreateTexture(nil, "BACKGROUND")
	header.Bar:SetAtlas("common-button-list-collapseExpand")
	header.Bar:SetAllPoints()
	header.BarHighlight = header:CreateTexture(nil, "HIGHLIGHT")
	header.BarHighlight:SetAtlas("common-button-list-collapseExpand")
	header.BarHighlight:SetAllPoints()
	header.BarHighlight:SetBlendMode("ADD")
	header.BarHighlight:SetAlpha(0.3)
	header.StateIcon = header:CreateTexture(nil, "BORDER")
	header.StateIcon:SetPoint("RIGHT", -8, -1)
	header.Name = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLeft")
	header.Name:SetPoint("LEFT", 10, 0)
	header.Arrow = header:CreateTexture(nil, "ARTWORK")
	header.Arrow:SetPoint("LEFT", 25, 0)
	header.SubName = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightLeft")
	header.SubName:SetPoint("LEFT", header.Arrow, "RIGHT", 4, 0)
	header.SubName:SetPoint("RIGHT", -10, 0)
	header:SetScript("OnClick", function(self)
		self.line.toggle()
		ns.RefreshWindow()
	end)
end

local function InitHeader(header, line)
	if not header.built then BuildHeader(header) end
	header.line = line
	local raid = line.header == 1
	header.Bar:SetShown(raid)
	header.BarHighlight:SetShown(raid)
	header.StateIcon:SetShown(raid)
	header.Name:SetShown(raid)
	header.Arrow:SetShown(not raid)
	header.SubName:SetShown(not raid)
	if raid then
		header.StateIcon:SetAtlas(line.collapsed and "common-button-list-plus" or "common-button-list-minus", true)
		header.Name:SetText(line.text)
	else
		header.Arrow:SetAtlas(line.collapsed and "campaign_headericon_closed" or "campaign_headericon_open", true)
		header.SubName:SetText(line.text)
	end
end

-- Header, footer and tabs ------------------------------------------------------------------------------------------

local function RoundText(m)
	local text = STATES[m.state] or m.state
	if m.state == "open" and ns.CanRoll() then text = L.ROUND_ROLL_NOW end
	if m.state == "reroll" then
		local rerolls = m.round - 1
		text = rerolls > 1 and L.ROUND_REROLL_N:format(rerolls) or L.STATE_REROLL
		if (m.slots or 1) > 1 then text = L.ROUND_FOR_SLOTS:format(text, m.slots) end
	end
	if m.state == "decided" and not m.winners[1] then text = L.ROUND_NO_ROLLS end
	if m.state == "awarded" and m.rev then text = L.ROUND_AWARDED:format(m.rev) end
	if m.ends then text = L.ROUND_TIME_LEFT:format(text, math.max(math.ceil(m.ends - GetTime()), 0)) end
	-- Where it dropped, when known.
	local source = m.boss and (m.instance .. " - " .. m.boss) or m.instance
	if source then text = Colored(source, GREY) .. "  ·  " .. text end
	return text
end

-- The loot history's timer bar, emptying as the round runs out.
local function UpdateTimer()
	local m = ns.live.mirror
	local timer = frame.Timer
	if not (m and m.ends and m.duration and m.duration > 0) then return timer:Hide() end
	local left = math.max(m.ends - GetTime(), 0) / m.duration
	timer:Show()
	timer.Fill:SetShown(left > 0)
	timer.Fill:SetWidth(math.max((timer:GetWidth() - 4) * left, 1))
end

local function UpdateHeader()
	local m = ns.live.mirror
	if m then
		frame:SetPortraitToAsset(ItemIcon(m.item) or ADDON_ICON)
		local text = ItemText(m.item)
		if m.copies > 1 then text = text .. Colored(" x" .. m.copies, HIGHLIGHT_FONT_COLOR) end
		if m.greed then text = text .. Colored(L.HEADER_GREED, HIGHLIGHT_FONT_COLOR) end
		frame.ItemName:SetText(text)
		frame.RoundText:SetText(RoundText(m))
	else
		frame:SetPortraitToAsset(ADDON_ICON)
		frame.ItemName:SetText("")
		frame.RoundText:SetText(ns.live.writer and L.HEADER_WAITING:format(ns.ColoredName(ns.WriterShownAs())) or "")
	end
	UpdateTimer()
end

-- The footer runs up to whichever buttons are showing: the ledger's revision and the officer who recorded it (not
-- while it's syncing, when it's moving), over the writer, always on two lines so they stay put. Test mode is in the
-- title, out of its way.
local function UpdateFooter()
	local ledger
	if ns.ledger then
		local head = ns.Head()
		if ns.SyncBusy() then
			ledger = L.FOOTER_REVISION_SYNCING:format(head.rev)
		elseif type(head.by) == "string" and head.by ~= "" then
			-- On the test menu's raider page, what you recorded is the made-up officer's, as the writer is.
			local by = head.by == UnitGUID("player") and ns.TestOfficer() or head.by
			ledger = L.FOOTER_REVISION_BY:format(head.rev, ns.ColoredName(by))
		else
			ledger = L.FOOTER_REVISION:format(head.rev)
		end
	else
		ledger = L.FOOTER_NO_LEDGER
	end
	local writer = ns.live.writer and L.WRITER:format(ns.ColoredName(ns.WriterShownAs())) or L.WRITER_NONE
	local status = frame.Status
	local primary, cancel = frame.Primary:IsShown(), frame.Cancel:IsShown()
	status:ClearAllPoints()
	status:SetPoint("LEFT", frame, "BOTTOMLEFT", FOOTER_LEFT, FOOTER_MIDDLE)
	if primary or cancel then
		status:SetPoint("RIGHT", primary and frame.Primary or frame.Cancel, "LEFT", -8, 0)
	else
		status:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -12, FOOTER_MIDDLE)
	end
	status:SetText(ledger .. "\n" .. writer)

	local title = "Pitiful Loot"
	if ns.IsTestMode() then
		title = title .. " " .. Colored(ns.ViewAsRaider() and L.TEST_WINDOW_TITLE_AS_RAIDER or L.TEST_WINDOW_TITLE, RED_FONT_COLOR)
	end
	frame:SetTitle(title)
	frame.Alert:SetShown(ns.warnings[1] ~= nil)
end

-- One main button for whatever the writer does next, as the base game's panels have, plus Cancel.
local function UpdateButtons()
	local m = ns.live.mirror
	local writer = AsWriter()
	local active = m and (m.state == "open" or m.state == "reroll")
	local decided = m and m.state == "decided"
	local label, action
	if writer and active then
		label, action = L.BUTTON_CLOSE_ROUND, ns.CloseRound
	elseif writer and decided and m.winners[1] then
		label, action = L.BUTTON_AWARD, ns.Award
	elseif writer and decided and not m.greed and ns.IsBoE(m.item) then
		label, action = L.BUTTON_GREED_ROLL, function() ns.StartRoll(m.item, m.copies, true) end
	elseif writer and decided and m.greed then
		label, action = L.BUTTON_KEEP, ns.KeepToSell
	elseif writer and decided and not ns.IsBoE(m.item) then
		label, action = L.BUTTON_DISENCHANT, ns.Disenchant
	elseif not writer and (IsInGroup() or ns.IsTestMode()) and AsOfficer() then
		label, action = L.BUTTON_BE_WRITER, ns.ClaimWriter
	end
	frame.Primary:SetShown(label ~= nil)
	frame.Primary:SetText(label or "")
	frame.Primary.action = action
	local cancel = writer and (active or decided) or false
	frame.Cancel:SetShown(cancel)
	frame.Primary:ClearAllPoints()
	if cancel then
		frame.Primary:SetPoint("RIGHT", frame.Cancel, "LEFT", -4, 0)
	else
		frame.Primary:SetPoint("BOTTOMRIGHT", -BUTTON_MARGIN, 12)
	end
end

local function UpdateTabs()
	local above
	for _, tab in ipairs(frame.Tabs) do
		tab:SetChecked(tab.view == view)
		if tab.view == "loot" then tab:SetShown(ns.loot.groups[1] ~= nil or view == "loot") end
		if tab.view == "raid" then tab:SetShown(ns.ShowsRaidTab()) end
		if tab:IsShown() then
			tab:ClearAllPoints()
			if above then
				tab:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -2)
			else
				tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -60)
			end
			above = tab
		end
	end
end

function ns.RefreshWindow()
	if not frame or not frame:IsShown() then return end
	if view == "raid" and not ns.ShowsRaidTab() then view = "session" end
	if view == "session" then
		lines = SessionLines()
	elseif view == "loot" then
		lines = LootLines()
	elseif view == "pity" then
		lines = PityLines()
	else
		lines = {}
	end
	-- The Options and Raid tabs have panels of their own in place of the list.
	local panel = view == "options" and frame.Options or view == "raid" and frame.Raid or nil
	frame.ScrollBox:SetShown(not panel)
	frame.ScrollBar:SetShown(not panel)
	frame.Options:SetShown(panel == frame.Options)
	frame.Raid:SetShown(panel == frame.Raid)
	if panel then panel:Refresh() end
	-- Redrawing hands the list's rows out again, which hides a row's tooltip (as when Shift's comparisons bring in item
	-- data); the row under the mouse gets it back.
	local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
	local hadTip = type(owner) == "table" and rawget(owner, "line") ~= nil
	frame.ScrollBox:SetDataProvider(CreateDataProvider(lines), ScrollBoxConstants.RetainScrollPosition)
	if hadTip then
		frame.ScrollBox:ForEachFrame(function(row)
			if row.line and row:IsMouseOver() then ShowTooltip(row, row.line) end
		end)
	end
	local empty = EMPTY[view]
	if view == "loot" and ns.loot.groups[1] then empty = L.EMPTY_LOOT_HIDDEN end
	if view == "raid" and (IsInGroup() or ns.IsTestMode()) then empty = "" end
	local m = ns.live.mirror
	if view == "session" and m then
		empty = (m.state == "open" or m.state == "reroll") and L.EMPTY_NOT_ROLLED_YET or L.EMPTY_NO_ONE_ROLLED
	end
	frame.Empty:SetText(lines[1] and "" or empty)
	-- With nothing to show on the Roll tab and no raid on, the way to the test raid, for anyone new: gone once they've
	-- finished it (5.5).
	local menu = ns.TestMenu and ns.TestMenu()
	frame.TryTest:SetShown(view == "session" and not lines[1] and not IsInRaid() and not (menu and menu:IsShown())
		and not ns.saved.tutorialFinished)
	UpdateHeader()
	UpdateButtons()
	UpdateFooter()
	UpdateTabs()
end

local function SetView(name)
	view = name
	if name == "raid" then ns.InspectRoles(true) end
	ns.RefreshWindow()
end
ns.SetWindowView = SetView

local function Texture(parent, layer, atlas, subLevel)
	local texture = parent:CreateTexture(nil, layer, nil, subLevel)
	texture:SetAtlas(atlas)
	return texture
end

local SECTION_GAP = 12 -- between a section's title and the options either side of it

-- The Options tab: the options (Options.lua) with the base game's own controls, scrolling if the window is too short
-- for them all. Officer options only show for officers who tick the box in the bottom right corner.
local function CreateOptions(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 20, -92)
	scroll:SetPoint("BOTTOMRIGHT", -30, 50)
	scroll.ScrollBar:SetHideIfUnscrollable(true)
	scroll.ScrollBar:ClearAllPoints()
	scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 7, 0)
	scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 7, 0)
	local panel = CreateFrame("Frame", nil, scroll)
	panel:SetSize(WIDTH - 50, 1)
	scroll:SetScrollChild(panel)
	scroll.Panel = panel
	-- { option, height, top, bottom, regions = { region, x, y offset }, update }: `top` and `bottom` are where the row's
	-- visible art starts and ends, below the row's top.
	local rows = {}

	local function Tooltip(region, option)
		region:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip_SetTitle(GameTooltip, option.title or option.name)
			GameTooltip_AddNormalLine(GameTooltip, option.tooltip, true)
			GameTooltip:Show()
		end)
		region:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end

	for _, option in ipairs(ns.OPTIONS) do
		local row = { option = option, regions = {} }
		if option.section then
			local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			header:SetText(option.section)
			row.regions[1] = { header, "TOPLEFT", 0, -6 }
			row.height, row.top, row.bottom = 28, 6, 18
		elseif option.kind == "checkbox" then
			local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
			box.Text:SetText(option.name)
			box.Text:SetFontObject("GameFontHighlight")
			box:SetScript("OnClick", function(self) ns.SetOption(option.key, self:GetChecked() and true or false) end)
			Tooltip(box, option)
			row.regions[1] = { box, "TOPLEFT", 4, 0 }
			row.update = function() box:SetChecked(ns.settings[option.key]) end
			row.height, row.top, row.bottom = 28, 5, 27 -- the box is drawn inside its 32 pixels
		elseif option.kind == "slider" then
			local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			label:SetText(option.name)
			-- The slider's value is drawn to its right, so the slider stops short of the edge to leave room for it.
			local slider = CreateFrame("Frame", nil, panel, "MinimalSliderWithSteppersTemplate")
			slider:SetSize(150, 20)
			slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
				if value ~= ns.settings[option.key] then ns.SetOption(option.key, value) end
			end, panel)
			Tooltip(slider, option)
			row.regions[1] = { label, "TOPLEFT", 8, -6 }
			row.regions[2] = { slider, "TOPRIGHT", -56, -2 }
			row.update = function()
				slider:Init(ns.settings[option.key], option.min, option.max, (option.max - option.min) / option.step,
					{ [MinimalSliderWithSteppersMixin.Label.Right] = option.format })
			end
			row.height, row.top, row.bottom = 30, 2, 22
		elseif option.kind == "dropdown" then
			local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			label:SetText(option.name)
			local dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
			dropdown:SetWidth(150)
			dropdown:SetupMenu(function(_, root)
				for _, choice in ipairs(option.choices) do
					root:CreateRadio(choice[2], function() return ns.settings[option.key] == choice[1] end,
						function() ns.SetOption(option.key, choice[1]) end)
				end
			end)
			Tooltip(dropdown, option)
			row.regions[1] = { label, "TOPLEFT", 8, -6 }
			row.regions[2] = { dropdown, "TOPRIGHT", -4, 0 }
			row.update = function() dropdown:GenerateMenu() end
			row.height, row.top, row.bottom = 32, 0, 25
		elseif option.kind == "profile" then
			-- Like Edit Mode's layouts: the profiles to pick from, then what can be done with them.
			local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			label:SetText(option.name)
			local dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
			dropdown:SetWidth(150)
			dropdown:SetupMenu(function(_, root)
				local db = ns.database
				local current, others = db:GetCurrentProfile(), {}
				for _, name in ipairs(ns.Profiles()) do
					root:CreateRadio(name, function() return db:GetCurrentProfile() == name end, function() db:SetProfile(name) end)
					if name ~= current then others[#others + 1] = name end
				end
				root:CreateDivider()
				root:CreateButton(L.PROFILE_NEW, function() StaticPopup_Show("PITIFULLOOT_NEW_PROFILE") end)
				local copy = others[1] and root:CreateButton(L.PROFILE_COPY)
				root:CreateButton(L.PROFILE_RESET, function() StaticPopup_Show("PITIFULLOOT_RESET_PROFILE", current) end)
				local delete = others[1] and root:CreateButton(L.PROFILE_DELETE)
				for _, name in ipairs(others) do
					copy:CreateButton(name, function() StaticPopup_Show("PITIFULLOOT_COPY_PROFILE", name, current, name) end)
					delete:CreateButton(name, function() StaticPopup_Show("PITIFULLOOT_DELETE_PROFILE", name, nil, name) end)
				end
			end)
			Tooltip(dropdown, option)
			row.regions[1] = { label, "TOPLEFT", 8, -6 }
			row.regions[2] = { dropdown, "TOPRIGHT", -4, 0 }
			row.update = function() dropdown:GenerateMenu() end
			row.height, row.top, row.bottom = 32, 0, 25
		end
		rows[#rows + 1] = row
	end

	-- Officers choose whether to see the officer options, in the bottom right corner, below the options.
	local officer = CreateFrame("CheckButton", nil, scroll, "UICheckButtonTemplate")
	officer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, 50)
	officer.Text:ClearAllPoints()
	officer.Text:SetPoint("RIGHT", officer, "LEFT", -2, 1)
	officer.Text:SetText(L.OPT_OFFICER)
	officer:SetScript("OnClick", function(self) ns.SetOption("showOfficerOptions", self:GetChecked() and true or false) end)
	Tooltip(officer, { name = L.OPT_OFFICER, tooltip = L.OPT_OFFICER_TIP })
	scroll.OfficerToggle = officer
	scroll.Rows = rows

	function scroll:Refresh()
		local isOfficer = AsOfficer()
		local showOfficer = isOfficer and ns.settings.showOfficerOptions
		officer:SetShown(isOfficer)
		officer:SetChecked(showOfficer)
		scroll:SetPoint("BOTTOMRIGHT", -30, isOfficer and 80 or 50)
		-- A section's title is as far below the option before it as its first option is below it.
		local y, previous = 0, nil
		for _, row in ipairs(rows) do
			local shown = (showOfficer or not row.option.officer) and not (row.option.member and isOfficer)
			if shown and previous and (row.option.section or previous.row.option.section) then
				y = previous.bottom - SECTION_GAP + row.top
			end
			for _, placed in ipairs(row.regions) do
				local region, point, x, offset = placed[1], placed[2], placed[3], placed[4]
				region:ClearAllPoints()
				region:SetPoint(point, x, y + offset)
				region:SetShown(shown)
			end
			if shown then
				if row.update then row.update() end
				previous = { row = row, bottom = y - row.bottom }
				y = y - row.height
			end
		end
		panel:SetHeight(math.max(-y, 1))
	end
	scroll:Hide()
	return scroll
end

-- The Raid tab ----------------------------------------------------------------------------------------------------

-- Every raider's role at a glance: the raid groups two to a row, each on a faint panel with its number, and in each a
-- line per raider of their role's icon and their name, in raid order as the game's raid frames have. A role nobody
-- knows has a question mark: light blue while their talents haven't been looked at yet (or are being looked at), red
-- when looking went wrong, so a problem stands out. Officers always have the tab; members can show it with an option,
-- just to look at. For officers, left-clicking a raider whose class has a choice of roles inspects them to read their
-- role from their talents, right-clicking sets it for everyone, and "Inspect Unknown" inspects every raider whose
-- role is unknown (Roles.lua).
local RAID_ROW_HEIGHT = 18
local RAID_GAP = 6 -- between the raid groups
local RAID_SUMMARY_HEIGHT = 26
local RAID_PANEL_WIDTH = WIDTH - 50
local RAID_COLUMN_WIDTH = (RAID_PANEL_WIDTH - RAID_GAP) / 2
local INSPECT_BUTTON_WIDTH = 120

local UNCHECKED_COLOR = LIGHTBLUE_FONT_COLOR or { r = 0.53, g = 0.67, b = 1 }
local INSPECTING_COLOR = CreateColor(1, 0.5, 0.1) -- orange: an inspect under way, for its bar and question mark
local DOT_TIME = 0.35 -- seconds each step of the "Inspecting..." dots shows for
local HIDDEN_DOTS = { r = 0, g = 0, b = 0 } -- the tooltip's background
local hoveredRaider -- the raider row whose tooltip is showing, to animate it (see the window's OnUpdate)

-- How a raider's role stands: "known"; "unchecked", while their talents haven't been looked at or are being looked
-- at; or "problem", when looking went wrong. The colour of each unknown kind, for its question mark and its line.
local function RaiderState(member)
	if ns.RoleInfo(member.guid) then return "known" end
	if ns.IsInspecting(member.guid) or not ns.RoleReason(member.guid) then return "unchecked" end
	return "problem"
end
local STATE_COLORS = { unchecked = UNCHECKED_COLOR, problem = RED_FONT_COLOR }
local STATE_TINT_ALPHA = { unchecked = 0.25, problem = 0.35 }

local function QuestionMark(state)
	return Colored("?", STATE_COLORS[state])
end

-- "Inspecting their talents" with dots that count up while it's under way. The dots not yet shown are drawn in black,
-- the tooltip's background, so the line keeps its width.
local function InspectingText()
	local shown = math.floor(GetTime() / DOT_TIME) % 4
	return L.RAID_INSPECTING .. ("."):rep(shown) .. Colored(("."):rep(3 - shown), HIDDEN_DOTS)
end

-- A raider's tooltip. Under their name, while their talents are being inspected, it says so, in light blue; or if
-- looking at their talents last went wrong, why, in red (not when it asked for the role to be set and an officer has,
-- or their last known role settles it).
-- Then their role, with its icon, in white, and where it came from if that isn't certain. An unknown role has a
-- question mark in place of the icon, with the fallback role rolls use. It's redrawn as things change while it's
-- hovered (InitRaiderRow).
local function ShowRaiderTooltip(owner, member)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, ns.ColoredName(member.guid, member.name))
	local role, source, by = ns.RoleInfo(member.guid)
	local reasonKey, busy = ns.RoleReason(member.guid), ns.IsInspecting(member.guid)
	if (source == "officer" or source == "known") and ns.SETTLED_REASONS[reasonKey] then reasonKey = nil end
	local reason = ns.UNKNOWN_REASONS[reasonKey or ""]
	if busy then
		GameTooltip_AddColoredLine(GameTooltip, InspectingText(), UNCHECKED_COLOR)
	elseif reason then
		GameTooltip_AddErrorLine(GameTooltip, reason, true)
	end
	if role then
		GameTooltip_AddHighlightLine(GameTooltip, RoleIcon(role) .. " " .. ns.ROLE_NAMES[role])
		local from = ns.ROLE_SOURCES[source]
		if from then GameTooltip_AddNormalLine(GameTooltip, from:format(by and ns.ColoredName(by) or "")) end
	else
		local fallback = ns.FallbackRole(member.class, ns.RoleReason(member.guid))
		GameTooltip_AddHighlightLine(GameTooltip, QuestionMark(RaiderState(member)) .. " " .. ns.ROLE_NAMES[fallback])
	end
	GameTooltip_AddNormalLine(GameTooltip, L.RAID_GROUP:format(member.subgroup or 1))
	if ns.RoleChoices(member) and AsOfficer() then
		ns.AddHint(GameTooltip, L.HINT_INSPECT)
		ns.AddHint(GameTooltip, L.HINT_SET_ROLE)
	end
	GameTooltip:Show()
end

-- An officer's menu for a raider: the roles their class can fill, and Automatic, which goes back to working it out.
local function ShowRaiderMenu(row, member)
	local choices = ns.RoleOptions(member)
	local function Set() return select(2, ns.RoleInfo(member.guid)) == "officer" end
	MenuUtil.CreateContextMenu(row, function(_, root)
		root:CreateTitle(member.name)
		for _, role in ipairs(ns.ROLE_ORDER) do
			if choices[role] then
				root:CreateRadio(RoleIcon(role) .. " " .. ns.ROLE_NAMES[role],
					function() return Set() and ns.RoleInfo(member.guid) == role end,
					function() ns.SetRole(member.guid, role) end)
			end
		end
		-- What Automatic would give, as its icon, or a question mark while that's unknown.
		local auto = ns.AutoRole(member.guid)
		root:CreateRadio(L.RAID_AUTOMATIC:format(auto and RoleIcon(auto) or QuestionMark("unchecked")),
			function() return not Set() end,
			function() if Set() then ns.SetRole(member.guid, nil) end end)
	end)
end

local function BuildRaiderRow(row)
	row.built = true
	row:SetSize(RAID_COLUMN_WIDTH, RAID_ROW_HEIGHT)
	row.Unknown = row:CreateTexture(nil, "BACKGROUND")
	row.Unknown:SetAllPoints()
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(ROLE_ICON_SIZE, ROLE_ICON_SIZE)
	row.Icon:SetPoint("LEFT", 2, 0)
	row.Mark = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.Mark:SetPoint("CENTER", row.Icon, "CENTER", 0, 0)
	row.Mark:SetText("?")
	row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 3, 0)
	row.Name:SetPoint("RIGHT", -12, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- Only officers can do anything here; members just look.
	row:SetScript("OnClick", function(self, button)
		local member = self.member
		if not (member and ns.RoleChoices(member) and AsOfficer()) then return end
		if button == "RightButton" then
			ShowRaiderMenu(self, member)
		else
			ns.InspectRaider(member)
		end
	end)
	row:SetScript("OnEnter", function(self)
		if not self.member then return end
		hoveredRaider = self
		ShowRaiderTooltip(self, self.member)
	end)
	row:SetScript("OnLeave", function()
		hoveredRaider = nil
		GameTooltip:Hide()
	end)
end

---@param row table a raider's row on the Raid tab
local function InitRaiderRow(row, member)
	if not row.built then BuildRaiderRow(row) end
	row.member = member
	local role = ns.RoleInfo(member.guid)
	local state = RaiderState(member)
	row.state = state
	local color = STATE_COLORS[state]
	row.Unknown:SetShown(color ~= nil)
	row.Mark:SetShown(color ~= nil)
	-- The bar and the question mark turn orange while their talents are being inspected; only how they look changes.
	row.inspecting = color ~= nil and ns.IsInspecting(member.guid) or nil
	if color then
		local tint = row.inspecting and INSPECTING_COLOR or color
		row.Unknown:SetColorTexture(tint.r, tint.g, tint.b, STATE_TINT_ALPHA[state])
		row.Mark:SetTextColor(tint.r, tint.g, tint.b)
	end
	row.Icon:SetShown(role ~= nil)
	if role then row.Icon:SetAtlas(ROLE_ICONS[role]) end
	row.Name:SetText(UnitIsConnected(member.unit) and ns.ColoredName(member.guid, member.name) or Colored(member.name, GREY))
	row:Show()
	-- A tooltip being hovered keeps up with what's happening, such as an inspect.
	if GameTooltip:IsOwned(row) then ShowRaiderTooltip(row, member) end
end

local function CreateRaid(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 20, -92)
	scroll:SetPoint("BOTTOMRIGHT", -30, 50)
	scroll.ScrollBar:SetHideIfUnscrollable(true)
	scroll.ScrollBar:ClearAllPoints()
	scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 7, 0)
	scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 7, 0)
	local panel = CreateFrame("Frame", nil, scroll)
	panel:SetSize(RAID_PANEL_WIDTH, 1)
	scroll:SetScrollChild(panel)
	scroll.Panel = panel
	-- How many of each role there are, then how many are unchecked and unknown, as question marks in their colours.
	local summary = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	summary:SetPoint("LEFT", panel, "TOPLEFT", 2, -RAID_SUMMARY_HEIGHT / 2 + 2)
	scroll.Summary = summary
	-- Officers inspect every raider whose role is unknown with this, in the top right; known roles are left alone.
	local inspect = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	inspect:SetSize(INSPECT_BUTTON_WIDTH, 22)
	inspect:SetPoint("TOPRIGHT", 0, -1)
	inspect:SetScript("OnClick", function() ns.InspectUnknown() end)
	inspect:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.RAID_INSPECT_UNKNOWN)
		GameTooltip_AddNormalLine(GameTooltip, L.RAID_INSPECT_UNKNOWN_TIP, true)
		GameTooltip:Show()
	end)
	inspect:SetScript("OnLeave", function() GameTooltip:Hide() end)
	scroll.Inspect = inspect
	local blocks, rows = {}, {}
	scroll.Rows = rows

	local function Block(i)
		if not blocks[i] then
			local block = { Background = panel:CreateTexture(nil, "BACKGROUND") }
			block.Background:SetColorTexture(0, 0, 0, 0.3)
			block.Number = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
			blocks[i] = block
		end
		return blocks[i]
	end

	function scroll:Refresh()
		local byGroup, counts = {}, {}
		for _, member in ipairs((IsInGroup() or ns.IsTestMode()) and ns.GroupMembers() or {}) do
			local group = member.subgroup or 1
			byGroup[group] = byGroup[group] or {}
			table.insert(byGroup[group], member)
			local key = ns.RoleInfo(member.guid) or RaiderState(member)
			counts[key] = (counts[key] or 0) + 1
		end
		local groups = {}
		for group = 1, 8 do
			if byGroup[group] then groups[#groups + 1] = group end
		end
		local parts = {}
		for _, role in ipairs(ns.ROLE_ORDER) do
			parts[#parts + 1] = CreateAtlasMarkup(ROLE_ICONS[role], ROLE_ICON_SIZE, ROLE_ICON_SIZE) .. " " .. (counts[role] or 0)
		end
		for _, state in ipairs({ "unchecked", "problem" }) do
			if counts[state] then parts[#parts + 1] = QuestionMark(state) .. " " .. counts[state] end
		end
		summary:SetText(groups[1] and table.concat(parts, "   ") or "")
		local officer = AsOfficer()
		inspect:SetShown(officer and groups[1] ~= nil)
		inspect:SetText(ns.IsSweeping() and L.RAID_INSPECTING_BUTTON or L.RAID_INSPECT_UNKNOWN)
		inspect:SetEnabled(not ns.IsSweeping() and ns.UnknownRaiders()[1] ~= nil)

		local used, y = 0, -RAID_SUMMARY_HEIGHT
		for i = 1, #groups, 2 do
			local pair = { groups[i], groups[i + 1] }
			local height = math.max(#byGroup[pair[1]], pair[2] and #byGroup[pair[2]] or 0) * RAID_ROW_HEIGHT + 4
			for column, group in ipairs(pair) do
				local x = (column - 1) * (RAID_COLUMN_WIDTH + RAID_GAP)
				local block = Block(i + column - 1)
				block.Background:ClearAllPoints()
				block.Background:SetPoint("TOPLEFT", x, y)
				block.Background:SetSize(RAID_COLUMN_WIDTH, height)
				block.Background:Show()
				block.Number:ClearAllPoints()
				block.Number:SetPoint("TOPRIGHT", block.Background, "TOPRIGHT", -4, -5)
				block.Number:SetText(group)
				block.Number:Show()
				for k, member in ipairs(byGroup[group]) do
					used = used + 1
					rows[used] = rows[used] or CreateFrame("Button", nil, panel)
					local row = rows[used]
					row:ClearAllPoints()
					row:SetPoint("TOPLEFT", x, y - 2 - (k - 1) * RAID_ROW_HEIGHT)
					InitRaiderRow(row, member)
				end
			end
			y = y - height - RAID_GAP
		end
		for i = #groups + 1, #blocks do
			blocks[i].Background:Hide()
			blocks[i].Number:Hide()
		end
		for i = used + 1, #rows do rows[i]:Hide() end
		panel:SetHeight(math.max(-y, 1))
	end
	scroll:Hide()
	return scroll
end

-- Crops the background art to the area it fills, keeping the art's own shape, so a taller window shows less of its
-- sides instead of stretching it. The crop centres on a point 60% of the way across, where the art is most
-- interesting, rather than its middle.
local function FitBackground()
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("groupfinder-background")
	local background = frame and frame.Background
	if not info or not background then return end
	local width, height = background:GetWidth(), background:GetHeight()
	if not width or not height or width <= 0 or height <= 0 then return end
	-- As NineSlice does: crop coordinates are in the art's whole file, so the texture shows the file, not the atlas.
	local source = info.file or info.filename
	if not source then return end
	background:SetTexture(source)
	local left, right, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	local artShape, areaShape = info.width / info.height, width / height
	if areaShape < artShape then
		-- Centred on the art's focus point, but never past either edge.
		local span = right - left
		local visible = span * areaShape / artShape
		local start = left + span * BACKGROUND_FOCUS - visible / 2
		start = math.max(left, math.min(start, right - visible))
		background:SetTexCoord(start, start + visible, top, bottom)
	else
		local half = (bottom - top) * artShape / areaShape / 2
		local middle = (top + bottom) / 2
		background:SetTexCoord(left, right, middle - half, middle + half)
	end
end

-- Anchors the window by its top left corner, where it's drawn, which can be somewhere else than its anchor says when
-- it's kept on screen. Anchored by the top, it grows downwards as it's resized.
local function AnchorWhereDrawn()
	local left, top = frame:GetLeft(), frame:GetTop()
	if not (left and top) then return end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint()
	ns.saved.position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

-- The window follows the mouse by itself rather than with the game's StartMoving, which now and then held it by
-- some other point than the one grabbed, until the next drag. The point where the mouse went down, measured from
-- where the window is drawn, stays under the mouse.
local dragger = CreateFrame("Frame")
dragger:Hide()
local grab -- the window's top left, from the mouse, when the mouse went down on it

local function Cursor()
	local x, y = GetCursorPosition()
	local scale = frame:GetEffectiveScale()
	return x / scale, y / scale
end

local function Grab()
	local left, top = frame:GetLeft(), frame:GetTop()
	if not (left and top) then return end
	local x, y = Cursor()
	grab = { x = left - x, y = top - y }
end

dragger:SetScript("OnUpdate", function()
	local x, y = Cursor()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + grab.x, y + grab.y)
end)

-- Resizing by hand too: the game's StartSizing could likewise go by a stale point, so the handle jumped away from the
-- mouse on every resize until the window was next moved. Anchored by its top left, the window's foot follows the
-- mouse up and down, within its height limits and the bottom of the screen.
local sizer = CreateFrame("Frame")
sizer:Hide()
local sizeFrom -- the mouse's height and the window's, when the handle went down

sizer:SetScript("OnUpdate", function()
	local _, y = Cursor()
	local height = sizeFrom.height + sizeFrom.y - y
	frame:SetHeight(math.max(MIN_HEIGHT, math.min(height, MAX_HEIGHT, frame:GetTop() or MAX_HEIGHT)))
end)

local function StartResizing()
	AnchorWhereDrawn()
	local _, y = Cursor()
	sizeFrom = { y = y, height = frame:GetHeight() }
	sizer:Show()
end

-- Ends a move or resize, as the mouse lets go or the window closes during one. Kept on screen, the window may be
-- drawn somewhere other than the mouse left it, so that's where it's kept.
local function StopMoving()
	grab, sizeFrom = nil, nil
	if not (dragger:IsShown() or sizer:IsShown()) then return end
	dragger:Hide()
	sizer:Hide()
	AnchorWhereDrawn()
	SavePosition()
end

-- The window drags from its frame, title bar and header. Those are covered by regions that take the mouse (the
-- item's tooltip, the list), so each is a handle that moves the window.
local function MakeDragHandle(region)
	region:EnableMouse(true)
	region:RegisterForDrag("LeftButton")
	region:HookScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then Grab() end
	end)
	region:SetScript("OnDragStart", function()
		if not grab then Grab() end
		if grab then dragger:Show() end
	end)
	region:SetScript("OnDragStop", StopMoving)
end

local function Create()
	frame = CreateFrame("Frame", "PitifulLootFrame", UIParent, "PortraitFrameTemplate")
	frame:SetSize(WIDTH, ns.saved.height or HEIGHT)
	frame:SetResizable(true)
	frame:SetResizeBounds(WIDTH, MIN_HEIGHT, WIDTH, MAX_HEIGHT)
	local position = ns.saved.position
	if position then
		frame:SetPoint(position.point, UIParent, position.relativePoint or position.point, position.x, position.y)
	else
		frame:SetPoint("CENTER")
	end
	frame:SetToplevel(true)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetDontSavePosition(true) -- the position is kept in the settings, not the client's layout cache
	frame:EnableMouse(true)
	MakeDragHandle(frame)
	MakeDragHandle(frame.TitleContainer)
	frame:HookScript("OnHide", StopMoving)
	frame.Dragger, frame.Sizer = dragger, sizer
	table.insert(UISpecialFrames, "PitifulLootFrame")
	frame:SetTitle("Pitiful Loot")

	-- The Who list's layout: a stone header over the group finder background, framed by the inside border.
	local background = Texture(frame, "BACKGROUND", "groupfinder-background", 1)
	frame.Background = background
	background:SetPoint("TOPLEFT", 4, -80)
	background:SetPoint("BOTTOMRIGHT", -4, 3)
	local header = Texture(frame, "BACKGROUND", "groupfinder-Stat-StoneBG", 2)
	header:SetPoint("TOPLEFT", 2, -21)
	header:SetPoint("BOTTOMRIGHT", background, "TOPRIGHT", 0, -7)
	local inside = Texture(frame, "BORDER", "common-insideframe")
	inside:SetPoint("TOPLEFT", 3, -78)
	inside:SetPoint("BOTTOMRIGHT", -4, 3)
	local topLine = Texture(frame, "ARTWORK", "groupfinder-ScrollLine")
	topLine:SetPoint("LEFT", background, "TOPLEFT", 0, -1)
	topLine:SetPoint("RIGHT", background, "TOPRIGHT", 0, -1)
	topLine:SetHeight(8)
	local bottomLine = Texture(frame, "ARTWORK", "groupfinder-ScrollLine")
	bottomLine:SetPoint("LEFT", frame, "BOTTOMLEFT", 4, 42)
	bottomLine:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -4, 42)
	bottomLine:SetHeight(8)

	-- The item being rolled for, its round, and the round's timer.
	frame.ItemName = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
	frame.ItemName:SetPoint("TOPLEFT", 62, -30)
	frame.ItemName:SetPoint("RIGHT", -40, 0)
	frame.ItemName:SetJustifyH("LEFT")
	frame.ItemName:SetWordWrap(false)
	frame.RoundText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.RoundText:SetPoint("TOPLEFT", frame.ItemName, "BOTTOMLEFT", 0, -4)
	frame.RoundText:SetJustifyH("LEFT")
	local itemHit = CreateFrame("Button", nil, frame)
	itemHit:SetPoint("TOPLEFT", 0, 0)
	itemHit:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", WIDTH - 40, -56)
	-- Officers can right-click the item to set its roles, as on the Loot tab.
	local function CanSetRoles(m)
		return m and AsOfficer() and not ns.ForEveryone(m.item)
	end
	itemHit:RegisterForClicks("RightButtonUp")
	itemHit:SetScript("OnEnter", function(self)
		local m = ns.live.mirror
		if not m then return end
		ShowTooltip(self, { item = m.item, hints = CanSetRoles(m) and { L.HINT_SET_ROLES } or nil })
	end)
	itemHit.UpdateTooltip = itemHit:GetScript("OnEnter") -- as the list's rows do, for Shift's comparisons
	itemHit:SetScript("OnClick", function(self)
		local m = ns.live.mirror
		if CanSetRoles(m) then ShowItemMenu(self, m.item) end
	end)
	itemHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
	MakeDragHandle(itemHit)
	frame.ItemHit = itemHit

	local timer = CreateFrame("Frame", nil, frame)
	timer:SetPoint("TOPLEFT", 62, -60)
	timer:SetPoint("RIGHT", -14, 0)
	timer:SetHeight(13)
	Texture(timer, "BACKGROUND", "lootroll-timer-background"):SetAllPoints()
	timer.Fill = Texture(timer, "ARTWORK", "lootroll-timer-fill")
	timer.Fill:SetPoint("LEFT", 2, 0)
	timer.Fill:SetHeight(9)
	Texture(timer, "OVERLAY", "lootroll-timer-border"):SetAllPoints()
	frame.Timer = timer

	-- A warning sign while something didn't match what this client saw (6.3).
	local alert = CreateFrame("Button", nil, frame)
	alert:SetSize(22, 22)
	alert:SetPoint("TOPRIGHT", -12, -30)
	alert:SetNormalTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
	alert:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.ALERT_TITLE, RED_FONT_COLOR)
		for i = math.max(#ns.warnings - WARNINGS_SHOWN + 1, 1), #ns.warnings do
			GameTooltip_AddNormalLine(GameTooltip, ns.warnings[i].text)
		end
		ns.AddHint(GameTooltip, L.HINT_DISMISS)
		GameTooltip:Show()
	end)
	alert:SetScript("OnLeave", function() GameTooltip:Hide() end)
	alert:SetScript("OnClick", function()
		ns.warnings = {}
		GameTooltip:Hide()
		ns.RefreshWindow()
	end)
	frame.Alert = alert

	-- The list, with the minimal scroll bar the base game's lists use.
	frame.ScrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	frame.ScrollBox:SetPoint("TOPLEFT", 12, -88)
	frame.ScrollBox:SetPoint("BOTTOMRIGHT", -26, 50)
	frame.ScrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	frame.ScrollBar:SetPoint("TOPLEFT", frame.ScrollBox, "TOPRIGHT", 5, -4)
	frame.ScrollBar:SetPoint("BOTTOMLEFT", frame.ScrollBox, "BOTTOMRIGHT", 5, -1)
	-- Headers are CheckButtons and rows Buttons, so the list keeps a separate pool of each.
	local scrollView = CreateScrollBoxListLinearView(0, 0, 0, 0, 2)
	scrollView:SetElementExtentCalculator(function(_, line)
		return line.header and HEADER_HEIGHT or (line.divider and DIVIDER_HEIGHT) or ROW_HEIGHT
	end)
	scrollView:SetElementFactory(function(factory, line)
		if line.header then
			factory("CheckButton", InitHeader)
		elseif line.divider then
			factory("Frame", InitDivider)
		else
			factory("Button", InitRow)
		end
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(frame.ScrollBox, frame.ScrollBar, scrollView)
	frame.Options = CreateOptions(frame)
	frame.Raid = CreateRaid(frame)

	local resize = CreateFrame("Button", nil, frame)
	resize:SetSize(32, 12)
	resize:SetPoint("TOP", frame, "BOTTOM", 0, 3)
	resize:SetFrameLevel(frame:GetFrameLevel() + 10)
	resize:RegisterForClicks("RightButtonUp")
	local handle = resize:CreateTexture(nil, "OVERLAY")
	handle:SetAtlas("lootroll-resizehandle")
	handle:SetAllPoints()
	resize:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		StartResizing()
	end)
	resize:SetScript("OnMouseUp", function(_, button)
		if button ~= "LeftButton" then return end
		StopMoving()
		ns.saved.height = math.floor(frame:GetHeight() + 0.5)
	end)
	resize:SetScript("OnClick", function()
		frame:SetHeight(HEIGHT)
		ns.saved.height = nil
	end)
	-- The handle's tooltip is only its hints, so it has none without them.
	resize:SetScript("OnEnter", function(self)
		if not ns.settings.tooltipHints then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip_SetTitle(GameTooltip, L.RESIZE_TITLE)
		ns.AddHint(GameTooltip, L.HINT_RESIZE_DRAG)
		ns.AddHint(GameTooltip, L.HINT_RESIZE_RESET)
		GameTooltip:Show()
	end)
	resize:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.Resize = resize
	frame.Empty = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.Empty:SetPoint("TOP", frame.ScrollBox, "TOP", 0, -24)
	frame.Empty:SetWidth(WIDTH - 60)
	frame.Empty:SetTextColor(GREY.r, GREY.g, GREY.b)
	local tryTest = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	tryTest:SetPoint("CENTER", frame.ScrollBox, "CENTER")
	tryTest:SetText(L.EMPTY_TRY_TEST_BUTTON)
	tryTest:SetSize(TextWidth(tryTest:GetFontString()) + 40, 22)
	local tryText = tryTest:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	tryText:SetPoint("BOTTOM", tryTest, "TOP", 0, 6)
	tryText:SetTextColor(GREY.r, GREY.g, GREY.b)
	tryText:SetText(L.EMPTY_TRY_TEST)
	tryTest:SetScript("OnClick", function() ns.ShowTestMenu() end)
	tryTest:Hide()
	frame.TryTest = tryTest

	frame.Status = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	frame.Status:SetJustifyH("LEFT")
	frame.Status:SetWordWrap(true)
	frame.Status:SetMaxLines(2)
	frame.Cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.Cancel:SetSize(CANCEL_WIDTH, 22)
	frame.Cancel:SetPoint("BOTTOMRIGHT", -BUTTON_MARGIN, 12)
	frame.Cancel:SetText(L.BUTTON_CANCEL)
	frame.Cancel:SetScript("OnClick", function() ns.CancelRoll() end)
	frame.Primary = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.Primary:SetSize(PRIMARY_WIDTH, 22)
	frame.Primary:SetScript("OnClick", function(self) if self.action then self.action() end end)

	-- Large side tabs down the right, as the group finder has.
	frame.Tabs = {}
	for i, info in ipairs(VIEWS) do
		local tab = CreateFrame("Frame", nil, frame, "LargeSideTabButtonTemplate")
		tab.view = info.key
		tab.tooltipText = info.label
		tab.Icon:SetTexture(info.icon)
		tab:SetFillToInterior(true)
		tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
			if button == "LeftButton" and upInside then SetView(tab.view) end
		end)
		if i == 1 then
			tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -60)
		else
			tab:SetPoint("TOPLEFT", frame.Tabs[i - 1], "BOTTOMLEFT", 0, -2)
		end
		frame.Tabs[i] = tab
	end

	-- The round's timer runs smoothly; the auto-roll countdown and the time left to trade items redraw the list when
	-- what they show changes.
	local elapsed, shown = 0, nil
	frame:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed < 0.1 then return end
		elapsed = 0
		-- A flipped roll held in place is let go, and the list sorted again, once the mouse is off it.
		if held then
			local over = false
			if view == "session" then
				frame.ScrollBox:ForEachFrame(function(row)
					if row.line and row.line.playerId == held.id and row:IsMouseOver() then over = true end
				end)
			end
			if not over then
				held = nil
				ns.RefreshWindow()
			end
		end
		-- The dots on a hovered raider's "Inspecting..." count up.
		local row = hoveredRaider
		if row and row.member and GameTooltip:IsOwned(row) and ns.IsInspecting(row.member.guid) then
			ShowRaiderTooltip(row, row.member)
		end
		local m = ns.live.mirror
		if m and m.ends then
			frame.RoundText:SetText(RoundText(m))
			UpdateTimer()
		end
		local now
		if view == "session" and m and m.autoRollAt then
			now = math.ceil(m.autoRollAt - GetTime())
		elseif view == "loot" and ns.PendingTrades()[1] then
			now = math.floor(GetServerTime() / TRADE_REFRESH)
		end
		if now ~= shown then
			shown = now
			if now then ns.RefreshWindow() end
		end
	end)
	frame:SetScript("OnShow", ns.RefreshWindow)
	frame:SetScript("OnSizeChanged", FitBackground)
	FitBackground()
	frame:Hide()
end

function ns.ShowWindow(tab)
	if not frame then Create() end
	if tab then view = tab end
	frame:Show()
	ns.RefreshWindow()
end

function ns.ToggleWindow()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		ns.ShowWindow()
	end
end

-- The addon compartment by the minimap (## AddonCompartmentFunc): left click for the window, right for its options.
-- Forever keeps that menu hidden, so the minimap button (MinimapButton.lua) is the one players see.
function PitifulLoot_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then
		ns.OpenOptions()
	else
		ns.ToggleWindow()
	end
end

-- For tests: the lines on show, and the window.
function ns.WindowLines()
	return lines
end

function ns.Window()
	return frame
end

local refreshQueued = false
local function RefreshSoon()
	if refreshQueued or not (frame and frame:IsShown()) then return end
	refreshQueued = true
	C_Timer.After(0, function()
		refreshQueued = false
		ns.RefreshWindow()
	end)
end

for _, name in ipairs({ "SESSION_CHANGED", "LEDGER_CHANGED", "ROSTER_CHANGED", "ROLES_CHANGED", "WARNINGS", "SYNC_CHANGED" }) do
	ns.Listen(name, RefreshSoon)
end
-- New loot opens its own group and the items awaiting trade, folds the other groups away, and opens the window on
-- the Loot tab (an option), unless you're hiding all of it. Loot caught up on after joining the group doesn't open
-- the window. An item's roll moving on only redraws it.
ns.Listen("LOOT_CHANGED", function(newGroup, restored)
	if newGroup then
		for _, group in ipairs(ns.loot.groups) do lootCollapsed[group.key] = group ~= newGroup or nil end
		lootCollapsed[TRADES] = nil
		if ns.settings.autoShowLoot and not restored and ShownItems(newGroup)[1] then return ns.ShowWindow("loot") end
	elseif view == "loot" and not ns.loot.groups[1] then
		view = "session"
	end
	RefreshSoon()
end)

-- Awarding or disenchanting takes the writer back to the Loot tab while there's loot left to deal with.
ns.Listen("ROLL_EVENT", function(kind)
	if (kind == "awarded" or kind == "disenchant") and AsWriter() and frame and frame:IsShown() and ns.LootToDistribute() then
		SetView("loot")
	end
end)

function ns.WindowView()
	return view
end
ns.On("GET_ITEM_INFO_RECEIVED", RefreshSoon)
