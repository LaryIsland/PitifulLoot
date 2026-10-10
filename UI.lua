local _, ns = ...

-- The window, made from Forever's own templates and art so it sits alongside the game's panels: a portrait frame
-- with side tabs like the group finder, a stone header and list rows like its Who list, and the timer bar and
-- checkmark from the loot history. It shows the roll in progress (5.2), the master looter's loot, and your pity.

local WIDTH, HEIGHT = 384, 524
local ROW_HEIGHT = 52
local VALUE_WIDTH = 104 -- room on the right of a row for its value
local DIVIDER_HEIGHT = 14
local DETAIL_COLUMNS = 3 -- a roll row's details: its roll, pity and off-spec, each in a column of the same width
-- Sized to their text ("Rerolled 62", "Pity +50", "Off-spec -20"), so the gaps between them look the same.
local COLUMN_WIDTHS = { 66, 54, 84 }
local COLUMN_OFFSETS = { 0, 66, 120 }
local ROW_WIDTH = WIDTH - 38 -- the list's width, inside its margins and scroll bar
local MIN_HEIGHT, MAX_HEIGHT = 400, 900
local ROLL_LOCK = 3 -- rerolls in a row after which the header calls the players roll-locked
local BACKGROUND_FOCUS = 0.6 -- how far across the background art its crop centres
local ADDON_ICON = "Interface\\Icons\\INV_Misc_Dice_02"
local VIEWS = {
	{ key = "session", label = "Roll", icon = "Interface\\Icons\\INV_Misc_Dice_02" },
	{ key = "pity", label = "My pity", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
	{ key = "loot", label = "Loot", icon = "Interface\\Icons\\INV_Box_02" }, -- only there once loot has been seen
	{ key = "options", label = "Options", icon = "Interface\\Icons\\INV_Misc_Gear_01" }, -- always at the bottom
}
local EMPTY = {
	session = "No roll in progress.",
	pity = "You haven't built up pity on anything yet.",
	loot = "Loot a boss as master looter to list its items here.",
	options = "",
}
local STATES = {
	open = "Rolling", reroll = "Reroll", decided = "Decided", cancelled = "Cancelled", awarded = "Awarded",
	disenchanted = "Disenchanted", kept = "Kept to sell",
}
local GREY = { r = 0.486, g = 0.518, b = 0.541 } -- FRIENDS_GRAY_COLOR, which the Who list uses for its details
local HEADER_HEIGHT = 26
local OTHER_RAID = "Other" -- items with no recorded raid, such as ones set by hand
local OTHER_BOSS = "Unknown boss"
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

local function Colored(text, color)
	if not color then return text end
	return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, text)
end

-- What the window offers: writer and officer controls, unless test mode is showing it as a member sees it.
local function AsWriter()
	return ns.AmWriter() and not ns.ViewAsMember()
end

local function AsOfficer()
	return ns.IsOfficer(ns.PlayerName()) and not ns.ViewAsMember()
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
local function TextWidth(fontString)
	local width = fontString.GetUnboundedStringWidth and fontString:GetUnboundedStringWidth() or fontString:GetStringWidth()
	return tonumber(width) or 0
end

-- Lines for each view. `cells` are the bare values; the rest is how a row shows them.

local function SessionLines()
	local m = ns.live.mirror
	local out = {}
	if not m then return out end
	local canFlip = AsWriter() and m.state == "open" and not m.greed and not ns.ForEveryone(m.item)
	for _, row in ipairs(ns.SessionRows()) do
		local id = row.id
		local spec = ""
		if row.roll then spec = row.offSpec and "off" or (row.unknownSpec and "?" or "main") end
		local columns = {
			row.roll and (row.round > 1 and "Rerolled %d" or "Rolled %d"):format(row.roll) or "",
			row.pity and row.pity > 0 and ("Pity +" .. row.pity) or "",
			row.offSpec and ("Off-spec %d"):format(ns.OFFSPEC_MODIFIER) or (row.unknownSpec and "Spec unknown") or "",
		}
		-- The roll and what went into it; the total is the number being hovered.
		local waiting = m.state == "reroll" and row.contender and "Hasn't rerolled" or "Hasn't rolled"
		local summary = { row.roll and tostring(row.roll) or (row.passed and "Passed") or waiting }
		if row.roll and row.pity and row.pity > 0 then summary[#summary + 1] = "+" .. row.pity end
		if row.roll and row.offSpec then summary[#summary + 1] = ("%d (off-spec)"):format(ns.OFFSPEC_MODIFIER) end
		local tip = { ns.ColoredName(id, row.name), table.concat(summary, " ") }
		if row.stale then tip = { tip[1], "Before the tie: " .. tip[2], waiting } end
		if canFlip and row.roll then
			tip[3] = "Click to count this roll as " .. (row.offSpec and "main-spec." or "off-spec.")
		end
		local click = canFlip and row.roll and function() ns.ToggleOffSpec(id) end or nil
		local mine = id == UnitGUID("player")
		local prompt
		if row.prompt then
			tip = { "Roll", "Does a /roll 1-100 for you. Everyone in the group sees it." }
			click = ns.Roll
			prompt = m.state == "reroll" and "Click to reroll" or "Click to roll"
			if row.autoRollAt then prompt = ("Auto-roll in %ds"):format(math.max(math.ceil(row.autoRollAt - GetTime()), 1)) end
		elseif mine and row.passed then
			tip[2] = "You passed. A /roll still counts if you change your mind."
		end
		-- Your chance of winning goes under the roll (until you've rolled, there's no roll above it). A roll from before
		-- a tie stays until its player rerolls, greyed out.
		local note = ""
		if row.passed then
			note = "Passed"
		elseif row.odds then
			note = Percent(row.odds) .. " chance"
		elseif (not row.roll or row.stale) and not (row.prompt or row.rolling) then
			note = waiting
		end
		-- In a reroll, a divider between the tied players, who come first, and everyone else.
		if m.contenders and not row.contender and out[1] and out[#out].contender then
			out[#out + 1] = { divider = true }
		end
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
			pass = row.prompt and ns.Pass or nil,
			passTip = m.state == "reroll" and "You won't reroll, so you lose the tie. You still gain pity for your first roll."
				or "You won't roll for this item. Typing /roll still counts if you change your mind.",
			winner = row.winner,
			contender = row.contender,
			faded = ((not row.roll or row.stale) and not (row.prompt or row.rolling)) or row.passed,
			tip = tip,
			click = click,
		}
	end
	return out
end

-- Each boss's loot, for everyone, under a header per boss in the order it was seen. Each item shows how its roll went
-- and your pity on it; awarded ones are greyed out with their winners. Only the writer gets buttons to start rolls.
local lootCollapsed = {}

-- "1h 42m", "28m", or "Expired".
local function TimeLeft(seconds)
	if seconds <= 0 then return "Expired" end
	local minutes = math.ceil(seconds / 60)
	if minutes < 60 then return minutes .. "m" end
	return ("%dh %02dm"):format(math.floor(minutes / 60), minutes % 60)
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
			if pending.id ~= me then detail[#detail + 1] = "For " .. ns.ColoredName(pending.id) end
			if pending.from and not ns.IsMe(pending.from) then detail[#detail + 1] = "From " .. ns.ColoredName(pending.from) end
			local click, hints
			if officer then
				local canTrade = left > 0 and pending.id ~= me and ns.HoldsItem(pending.item)
				hints = {}
				if canTrade then hints[1] = "Left-click to trade it to " .. ns.ColoredName(pending.id) .. "." end
				hints[#hints + 1] = left > 0 and "Right-click if it's been handed over." or "Right-click to clear it."
				click = function(button)
					if button == "RightButton" then
						ns.MarkTraded(pending.sid, pending.id)
					elseif canTrade then
						ns.OfferTrade(pending.id)
					end
				end
			end
			rows[#rows + 1] = {
				cells = { name = ns.ItemLink(pending.item), pity = "", spec = "trade" },
				icon = ItemIcon(pending.item),
				title = ns.ItemLink(pending.item),
				detail = table.concat(detail, "  ·  "),
				value = TimeLeft(left),
				valueColor = left < TRADE_WARNING and RED_FONT_COLOR or nil,
				note = left > 0 and "to trade" or nil,
				mine = pending.id == me,
				item = pending.item,
				click = click,
				hints = hints,
			}
		end
	end
	if not rows[1] then return end
	out[#out + 1] = {
		header = 1, key = TRADES, collapsed = lootCollapsed[TRADES], text = ("Awaiting trade (%d)"):format(#rows),
		toggle = function() lootCollapsed[TRADES] = not lootCollapsed[TRADES] or nil end,
	}
	if lootCollapsed[TRADES] then return end
	for _, row in ipairs(rows) do out[#out + 1] = row end
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
	local state, me = ns.ledger and ns.ledger.state, UnitGUID("player")
	for index, group in ipairs(ns.loot.groups) do
		local key = group.key
		local items = ShownItems(group)
		if items[1] then
			out[#out + 1] = {
				header = 1, key = key, collapsed = lootCollapsed[key],
				text = ("%s (%d)"):format(group.boss or ("Loot " .. index), #items),
				toggle = function() lootCollapsed[key] = not lootCollapsed[key] or nil end,
			}
		end
		for _, entry in ipairs(lootCollapsed[key] and {} or items) do
			local item = entry.item
			local done = ns.LootDone(entry)
			local detail = {}
			-- Once it's won, the winners show how many there were.
			if entry.copies > 1 and not done and entry.status ~= "decided" then detail[#detail + 1] = entry.copies .. " copies" end
			if entry.boe then detail[#detail + 1] = "Binds on Equip" end
			local status
			if entry.status == "rolling" then
				status = Colored("Rolling now", NORMAL_FONT_COLOR)
			elseif entry.status == "decided" then
				status = "Won by " .. NameList(entry.pending or {})
			elseif entry.status == "disenchanted" or entry.status == "kept" then
				local fate = entry.status == "kept" and "kept to sell" or "disenchanted"
				status = entry.winners[1] and ("Awarded to %s, the rest %s"):format(NameList(entry.winners), fate)
					or (fate:gsub("^%l", string.upper))
			elseif done then
				status = "Awarded to " .. NameList(entry.winners)
			elseif entry.winners[1] then
				status = ("%d of %d awarded: %s"):format(#entry.winners, entry.copies, NameList(entry.winners))
			elseif entry.status == "none" then
				status = "No one rolled"
			end
			if status then detail[#detail + 1] = status end
			local click, hints
			if canStart and (entry.status == "waiting" or entry.status == "none") then
				local copies = entry.copies - #entry.winners
				hints = { "Left-click to start a roll." }
				if entry.boe then hints[2] = "Right-click to start a greed roll." end
				click = function(button)
					if button == "LeftButton" then
						ns.StartRoll(item, copies)
					elseif button == "RightButton" and entry.boe then
						ns.StartRoll(item, copies, true)
					end
				end
			end
			-- Your own pity on it, on the right, if you have any.
			local won = state and state:HasWon(me, item)
			local pity = state and state:GetPity(me, item, false, GetServerTime()) or 0
			local value, note = "", nil
			if won then
				note = "You've won this"
			elseif pity > 0 then
				value, note = "+" .. pity, "Your pity"
			end
			local name = C_Item.GetItemInfo(item)
			out[#out + 1] = {
				cells = { name = ns.ItemLink(item), pity = "x" .. entry.copies, spec = entry.status },
				icon = ItemIcon(item),
				title = done and Colored(name or ns.ItemLink(item), GREY) or ns.ItemLink(item),
				detail = table.concat(detail, "  ·  "),
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
	local collapsed = ns.settings.collapsed
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
	local state, me = ns.ledger and ns.ledger.state, UnitGUID("player")
	if not state then return out end
	local now = GetServerTime()
	local byBoss = ns.settings.pityByBoss
	local raids = {}
	local function Add(item, pity, note)
		local source = state.sources[item]
		local raid = source and source.instance or OTHER_RAID
		local boss = byBoss and (source and source.boss or OTHER_BOSS) or ""
		raids[raid] = raids[raid] or { count = 0, bosses = {} }
		raids[raid].count = raids[raid].count + 1
		raids[raid].bosses[boss] = raids[raid].bosses[boss] or {}
		local chance = pity and pity > 0 and ns.HeadToHead(pity) or nil
		table.insert(raids[raid].bosses[boss], {
			cells = { name = ns.ItemLink(item), pity = pity and ("+" .. pity) or "", spec = note },
			icon = ItemIcon(item),
			title = ns.ItemLink(item),
			detail = note,
			value = pity and ("+" .. pity) or "",
			note = chance and ("%d%% vs 0 pity"):format(chance * 100 + 0.5) or nil,
			sort = pity or -1,
			winner = note == "Won",
			item = item,
		})
	end
	-- Pity that's decayed to nothing isn't pity any more.
	for _, greed in ipairs({ false, true }) do
		for item in pairs((greed and state.greed or state.pity)[me] or {}) do
			local pity = state:GetPity(me, item, greed, now)
			if pity > 0 then Add(item, pity, greed and "Greed" or "Need") end
		end
	end
	if not ns.settings.hideWon then
		for item in pairs(state.won[me] or {}) do Add(item, nil, "Won") end
	end

	if focusRaid then FocusRaid(raids) end
	local collapsed = ns.settings.collapsed
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
		GameTooltip:SetItemByID(line.item)
	else
		GameTooltip_SetTitle(GameTooltip, line.tip[1])
		for i = 2, #line.tip do GameTooltip_AddNormalLine(GameTooltip, line.tip[i]) end
	end
	for _, hint in ipairs(line.hints or {}) do GameTooltip_AddInstructionLine(GameTooltip, hint) end
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
	row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalMed1")
	row.Title:SetJustifyH("LEFT")
	row.Title:SetWordWrap(false)
	row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Detail:SetJustifyH("LEFT")
	row.Detail:SetWordWrap(false)
	row.Detail:SetTextColor(GREY.r, GREY.g, GREY.b)
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
	row.Value:SetPoint("TOPRIGHT", -12, -9)
	row.Note = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Note:SetPoint("BOTTOMRIGHT", -12, 11)
	row.Note:SetTextColor(GREY.r, GREY.g, GREY.b)
	row.Check = row:CreateTexture(nil, "OVERLAY")
	row.Check:SetAtlas("lootroll-icon-checkmark", true)
	-- "Click to roll", across the middle of your own row while you can roll.
	row.Prompt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	-- Passing, with the group loot roll's own pass button, in the top right corner of your row: apart from the rest of
	-- the row, which rolls.
	row.Pass = CreateFrame("Button", nil, row)
	row.Pass:SetSize(PASS_SIZE, PASS_SIZE)
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

	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self, button) if self.line and self.line.click then self.line.click(button) end end)
	row:SetScript("OnEnter", function(self) if self.line then ShowTooltip(self, self.line) end end)
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
	-- Text runs to the right edge unless the row has a value, a note or a button there.
	local right = ((line.value or "") ~= "" or (line.note or "") ~= "" or line.prompt or line.pass) and -VALUE_WIDTH or -12
	row.Title:ClearAllPoints()
	row.Title:SetPoint("TOPLEFT", left, -9)
	row.Title:SetPoint("RIGHT", right, 0)
	row.Title:SetText(line.title)
	row.Detail:ClearAllPoints()
	row.Detail:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -6)
	row.Detail:SetPoint("RIGHT", right, 0)
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
	row.Value:SetText(line.value or "")
	local valueColor = line.valueColor or line.mineColor or (line.contender and NORMAL_FONT_COLOR) or HIGHLIGHT_FONT_COLOR
	row.Value:SetTextColor(valueColor.r, valueColor.g, valueColor.b)
	row.Note:SetText(line.note or "")
	row.Pass:SetShown(line.pass ~= nil)
	-- The checkmark sits beside the value, or in the middle of the right edge when there's no value.
	row.Check:ClearAllPoints()
	if (line.value or "") ~= "" then
		row.Check:SetPoint("RIGHT", row.Value, "LEFT", -4, 0)
	else
		row.Check:SetPoint("RIGHT", -12, 0)
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
	if m.state == "open" and ns.CanRoll() then text = "Roll now" end
	if m.state == "reroll" then
		local rerolls = m.round - 1
		text = rerolls > ROLL_LOCK and ("Roll-locked! Reroll %d"):format(rerolls)
			or rerolls > 1 and ("Reroll %d"):format(rerolls) or "Reroll"
		if (m.slots or 1) > 1 then text = ("%s for %d"):format(text, m.slots) end
	end
	if m.state == "decided" and not m.winners[1] then text = "No rolls" end
	if m.state == "awarded" and m.rev then text = ("Awarded (revision %d)"):format(m.rev) end
	if m.ends then text = ("%s: %ds left"):format(text, math.max(math.ceil(m.ends - GetTime()), 0)) end
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
		local text = ns.ItemLink(m.item)
		if m.copies > 1 then text = text .. Colored(" x" .. m.copies, HIGHLIGHT_FONT_COLOR) end
		if m.greed then text = text .. Colored(" (greed)", HIGHLIGHT_FONT_COLOR) end
		frame.ItemName:SetText(text)
		frame.RoundText:SetText(RoundText(m))
	else
		frame:SetPortraitToAsset(ADDON_ICON)
		frame.ItemName:SetText("")
		frame.RoundText:SetText(ns.live.writer and ("Waiting for " .. ns.ColoredName(ns.live.writer) .. " to start a roll.") or "")
	end
	UpdateTimer()
end

-- The footer runs up to whichever buttons are showing, on one line if it fits and two if not, so a long writer's
-- name never cuts it short. Test mode is in the title, out of its way.
local function UpdateFooter()
	local ledger
	if ns.ledger then
		ledger = ("Revision %d"):format((ns.ledger:Revision()))
		if ns.SyncBusy() then ledger = ledger .. ", syncing" end
	else
		ledger = "No guild ledger"
	end
	local writer = "Writer: " .. (ns.live.writer and ns.ColoredName(ns.live.writer) or "none")
	local status = frame.Status
	local primary, cancel = frame.Primary:IsShown(), frame.Cancel:IsShown()
	status:ClearAllPoints()
	status:SetPoint("LEFT", frame, "BOTTOMLEFT", FOOTER_LEFT, FOOTER_MIDDLE)
	local right = 12
	if primary or cancel then
		status:SetPoint("RIGHT", primary and frame.Primary or frame.Cancel, "LEFT", -8, 0)
		right = BUTTON_MARGIN + 8 + (cancel and CANCEL_WIDTH or 0) + (primary and PRIMARY_WIDTH or 0) + (primary and cancel and 4 or 0)
	else
		status:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -right, FOOTER_MIDDLE)
	end
	status:SetText(ledger .. "  ·  " .. writer)
	if TextWidth(status) > WIDTH - FOOTER_LEFT - right then status:SetText(ledger .. "\n" .. writer) end

	local title = "Pitiful Loot"
	if ns.IsTestMode() then
		title = title .. " " .. Colored(ns.ViewAsMember() and "(test mode, as a member)" or "(test mode)", RED_FONT_COLOR)
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
		label, action = "Close round", ns.CloseRound
	elseif writer and decided and m.winners[1] then
		label, action = "Award", ns.Award
	elseif writer and decided and not m.greed and ns.IsBoE(m.item) then
		label, action = "Greed roll", function() ns.StartRoll(m.item, m.copies, true) end
	elseif writer and decided and m.greed then
		label, action = "Keep to sell", ns.KeepToSell
	elseif writer and decided and not ns.IsBoE(m.item) then
		label, action = "Disenchant", ns.Disenchant
	elseif not writer and IsInGroup() and AsOfficer() then
		label, action = "Be the writer", ns.ClaimWriter
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
	if view == "session" then
		lines = SessionLines()
	elseif view == "loot" then
		lines = LootLines()
	elseif view == "pity" then
		lines = PityLines()
	else
		lines = {}
	end
	local options = view == "options"
	frame.ScrollBox:SetShown(not options)
	frame.ScrollBar:SetShown(not options)
	frame.Options:SetShown(options)
	if options then frame.Options:Refresh() end
	frame.ScrollBox:SetDataProvider(CreateDataProvider(lines), ScrollBoxConstants.RetainScrollPosition)
	local empty = EMPTY[view]
	if view == "loot" and ns.loot.groups[1] then empty = "None of the loot is for you." end
	frame.Empty:SetText(lines[1] and "" or empty)
	UpdateHeader()
	UpdateButtons()
	UpdateFooter()
	UpdateTabs()
end

local function SetView(name)
	view = name
	ns.RefreshWindow()
end
ns.SetWindowView = SetView

local function Texture(parent, layer, atlas, subLevel)
	local texture = parent:CreateTexture(nil, layer, nil, subLevel)
	texture:SetAtlas(atlas)
	return texture
end

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
	local rows = {} -- { option, height, regions = { region, x, y offset }, update }

	local function Tooltip(region, option)
		region:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip_SetTitle(GameTooltip, option.name)
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
			row.height = 28
		elseif option.kind == "checkbox" then
			local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
			box.Text:SetText(option.name)
			box.Text:SetFontObject("GameFontHighlight")
			box:SetScript("OnClick", function(self) ns.SetOption(option.key, self:GetChecked() and true or false) end)
			Tooltip(box, option)
			row.regions[1] = { box, "TOPLEFT", 4, 0 }
			row.update = function() box:SetChecked(ns.settings[option.key]) end
			row.height = 28
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
			row.height = 30
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
			row.height = 32
		end
		rows[#rows + 1] = row
	end

	-- Officers choose whether to see the officer options, in the bottom right corner, below the options.
	local officer = CreateFrame("CheckButton", nil, scroll, "UICheckButtonTemplate")
	officer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, 50)
	officer.Text:ClearAllPoints()
	officer.Text:SetPoint("RIGHT", officer, "LEFT", -2, 1)
	officer.Text:SetText("Officer options")
	officer:SetScript("OnClick", function(self) ns.SetOption("showOfficerOptions", self:GetChecked() and true or false) end)
	Tooltip(officer, { name = "Officer options",
		tooltip = "Show the options for running rolls: announcements, roll times and which loot is listed." })
	scroll.OfficerToggle = officer

	function scroll:Refresh()
		local isOfficer = AsOfficer()
		local showOfficer = isOfficer and ns.settings.showOfficerOptions
		officer:SetShown(isOfficer)
		officer:SetChecked(showOfficer)
		scroll:SetPoint("BOTTOMRIGHT", -30, isOfficer and 80 or 50)
		local y = 0
		for _, row in ipairs(rows) do
			local shown = showOfficer or not row.option.officer
			for _, placed in ipairs(row.regions) do
				local region, point, x, offset = placed[1], placed[2], placed[3], placed[4]
				region:ClearAllPoints()
				region:SetPoint(point, x, y + offset)
				region:SetShown(shown)
			end
			if shown then
				if row.update then row.update() end
				y = y - row.height
			end
		end
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

-- The window drags from its frame, title bar and header. Those are covered by regions that take the mouse (the
-- item's tooltip, the list), so each is a handle that moves the window.
local function MakeDragHandle(region)
	region:EnableMouse(true)
	region:RegisterForDrag("LeftButton")
	region:SetScript("OnDragStart", function() frame:StartMoving() end)
	region:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		local point, _, relativePoint, x, y = frame:GetPoint()
		ns.settings.position = { point = point, relativePoint = relativePoint, x = x, y = y }
	end)
end

local function Create()
	frame = CreateFrame("Frame", "PitifulLootFrame", UIParent, "PortraitFrameTemplate")
	frame:SetSize(WIDTH, ns.settings.height or HEIGHT)
	frame:SetResizable(true)
	frame:SetResizeBounds(WIDTH, MIN_HEIGHT, WIDTH, MAX_HEIGHT)
	local position = ns.settings.position
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
	itemHit:SetScript("OnEnter", function(self)
		local m = ns.live.mirror
		if m then ShowTooltip(self, { item = m.item }) end
	end)
	itemHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
	MakeDragHandle(itemHit)

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
		GameTooltip_SetTitle(GameTooltip, "Something didn't match", RED_FONT_COLOR)
		for i = math.max(#ns.warnings - WARNINGS_SHOWN + 1, 1), #ns.warnings do
			GameTooltip_AddNormalLine(GameTooltip, ns.warnings[i].text)
		end
		GameTooltip_AddInstructionLine(GameTooltip, "Click to dismiss.")
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

	local resize = CreateFrame("Button", nil, frame)
	resize:SetSize(32, 12)
	resize:SetPoint("TOP", frame, "BOTTOM", 0, 3)
	resize:SetFrameLevel(frame:GetFrameLevel() + 10)
	resize:RegisterForClicks("RightButtonUp")
	local handle = resize:CreateTexture(nil, "OVERLAY")
	handle:SetAtlas("lootroll-resizehandle")
	handle:SetAllPoints()
	resize:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then frame:StartSizing("BOTTOM") end
	end)
	resize:SetScript("OnMouseUp", function(_, button)
		if button ~= "LeftButton" then return end
		frame:StopMovingOrSizing()
		ns.settings.height = math.floor(frame:GetHeight() + 0.5)
	end)
	resize:SetScript("OnClick", function()
		frame:SetHeight(HEIGHT)
		ns.settings.height = nil
	end)
	resize:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip_SetTitle(GameTooltip, "Resize")
		GameTooltip_AddInstructionLine(GameTooltip, "Drag to make the window taller or shorter.")
		GameTooltip_AddInstructionLine(GameTooltip, "Right-click to reset its size.")
		GameTooltip:Show()
	end)
	resize:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.Resize = resize
	frame.Empty = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.Empty:SetPoint("TOP", frame.ScrollBox, "TOP", 0, -24)
	frame.Empty:SetWidth(WIDTH - 60)
	frame.Empty:SetTextColor(GREY.r, GREY.g, GREY.b)

	frame.Status = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	frame.Status:SetJustifyH("LEFT")
	frame.Status:SetWordWrap(true)
	frame.Status:SetMaxLines(2)
	frame.Cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.Cancel:SetSize(CANCEL_WIDTH, 22)
	frame.Cancel:SetPoint("BOTTOMRIGHT", -BUTTON_MARGIN, 12)
	frame.Cancel:SetText("Cancel")
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

-- The addon compartment by the minimap: left click for the window, right for its options. It's added here rather
-- than from the TOC so the Minimap Button option can take it out again, which the compartment can't do for an entry
-- the TOC adds.
local compartment = {
	text = "Pitiful Loot",
	icon = ADDON_ICON,
	func = function(_, input)
		if input and input.buttonName == "RightButton" then
			ns.OpenOptions()
		else
			ns.ToggleWindow()
		end
	end,
}

local function UpdateCompartment()
	local menu = AddonCompartmentFrame
	if not (menu and menu.registeredAddons and menu.RegisterAddon) then return end
	local index
	for i, data in ipairs(menu.registeredAddons) do
		if data == compartment then index = i end
	end
	if ns.settings.minimapButton and not index then
		menu:RegisterAddon(compartment)
	elseif not ns.settings.minimapButton and index then
		table.remove(menu.registeredAddons, index)
		menu:UpdateDisplay()
	end
end
ns.On("PLAYER_LOGIN", UpdateCompartment)
ns.Listen("SETTINGS_CHANGED", function(key)
	if key == "minimapButton" then UpdateCompartment() end
end)

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

for _, name in ipairs({ "SESSION_CHANGED", "LEDGER_CHANGED", "ROSTER_CHANGED", "WARNINGS", "SYNC_CHANGED" }) do
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
