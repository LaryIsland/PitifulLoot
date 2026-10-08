local _, ns = ...

-- The window: the roll in progress with each player's pity, spec, roll and odds (5.2), the master looter's loot,
-- and your own pity. The writer's controls sit along the bottom.

local WIDTH, HEIGHT = 480, 440
local ROW_HEIGHT = 16
local ROW_COUNT = 16
local ACTION_WIDTH = 64

local COLUMNS = {
	{ key = "name", width = 160, justify = "LEFT" },
	{ key = "pity", width = 45, justify = "RIGHT" },
	{ key = "spec", width = 55, justify = "CENTER" },
	{ key = "roll", width = 60, justify = "RIGHT" },
	{ key = "total", width = 50, justify = "RIGHT" },
	{ key = "odds", width = 60, justify = "RIGHT" },
}
local HEADERS = {
	session = { name = "Player", pity = "Pity", spec = "Spec", roll = "Roll", total = "Total", odds = "Odds" },
	loot = { name = "Item", pity = "Copies" },
	pity = { name = "Item", pity = "Pity", spec = "" },
}
local STATES = {
	open = "Rolling", reroll = "Reroll", decided = "Decided", cancelled = "Cancelled", awarded = "Awarded",
}
local WHITE, GREY, GREEN, YELLOW = { 1, 1, 1 }, { 0.6, 0.6, 0.6 }, { 0.3, 1, 0.3 }, { 1, 0.85, 0.2 }

local frame
local rows, headers, tabs, buttons = {}, {}, {}, {}
local view, offset, lines = "session", 0, {}

local function Text(parent, font, justify)
	local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	text:SetJustifyH(justify or "LEFT")
	return text
end

local function Button(parent, label, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 20)
	button:SetText(label)
	button:SetScript("OnClick", onClick)
	return button
end

local function Percent(chance)
	if chance >= 0.995 or chance == 0 then return ("%d%%"):format(chance * 100 + 0.5) end
	return ("%.1f%%"):format(chance * 100)
end

-- Lines for each view: { cells = {column = text}, color, link or tip, click, actions = {{label, func}} }.

local function SessionLines()
	local m = ns.live.mirror
	local out = {}
	if not m then return out end
	for _, row in ipairs(ns.SessionRows()) do
		local roll = row.roll and tostring(row.roll) or "-"
		if row.round and row.round > 1 then roll = roll .. " (r" .. row.round .. ")" end
		local spec = ""
		if row.roll then spec = row.offSpec and "off" or (row.unknownSpec and "?" or "main") end
		local color = row.winner and GREEN or (row.contender and YELLOW) or (row.roll and WHITE) or GREY
		local id = row.id
		out[#out + 1] = {
			cells = {
				name = row.name, pity = row.pity and ("+" .. row.pity) or "", spec = spec, roll = roll,
				total = row.total and tostring(row.total) or "", odds = row.odds and Percent(row.odds) or "",
			},
			color = color,
			tip = row.roll and ns.Breakdown(m, id) or (row.name .. " hasn't rolled"),
			click = function() ns.ToggleOffSpec(id) end,
		}
	end
	return out
end

local function LootLines()
	local out = {}
	for _, loot in ipairs(ns.loot) do
		local actions = { { "Roll", function() ns.StartRoll(loot.item, loot.copies) end } }
		if loot.boe then actions[2] = { "Greed", function() ns.StartRoll(loot.item, loot.copies, true) end } end
		out[#out + 1] = { cells = { name = loot.link, pity = "x" .. loot.copies }, color = WHITE, link = loot.link, actions = actions }
	end
	return out
end

local function PityLines()
	local out = {}
	local state, me = ns.ledger and ns.ledger.state, UnitGUID("player")
	if not state then return out end
	local now = GetServerTime()
	local function Add(item, text, note, color)
		out[#out + 1] = { cells = { name = ns.ItemLink(item), pity = text, spec = note }, color = color, link = ns.ItemLink(item) }
	end
	for item in pairs(state.pity[me] or {}) do Add(item, "+" .. state:GetPity(me, item, false, now), "", WHITE) end
	for item in pairs(state.greed[me] or {}) do Add(item, "+" .. state:GetPity(me, item, true, now), "greed", WHITE) end
	for item in pairs(state.won[me] or {}) do Add(item, "", "won", GREEN) end
	return out
end

local function StatusText()
	local parts = {}
	if ns.ledger then
		local rev, head = ns.ledger:Revision()
		parts[#parts + 1] = ("Revision %d (%s)"):format(rev, head:sub(1, 8))
		if ns.SyncBusy() then parts[#parts + 1] = "syncing" end
	else
		parts[#parts + 1] = "No guild ledger"
	end
	parts[#parts + 1] = "Writer: " .. (ns.live.writer or "none")
	return table.concat(parts, "  ·  ")
end

local function RoundText(m)
	local text = STATES[m.state] or m.state
	if m.state == "reroll" then text = ("Reroll for %d"):format(m.slots or 1) end
	if m.state == "decided" and not m.winners[1] then text = "No rolls" end
	if m.state == "awarded" and m.rev then text = ("Awarded (revision %d)"):format(m.rev) end
	if m.ends then text = ("%s: %ds"):format(text, math.max(math.ceil(m.ends - GetTime()), 0)) end
	return text
end

local function Render()
	for i, row in ipairs(rows) do
		local line = lines[i + offset]
		row.line = line
		row:SetShown(line ~= nil)
		if line then
			for _, column in ipairs(COLUMNS) do
				local cell = row.cells[column.key]
				cell:SetText(line.cells[column.key] or "")
				cell:SetTextColor(line.color[1], line.color[2], line.color[3])
			end
			for a, action in ipairs(row.actions) do
				local spec = line.actions and line.actions[a]
				action:SetShown(spec ~= nil)
				if spec then
					action:SetText(spec[1])
					action.func = spec[2]
				end
			end
		end
	end
end

local function UpdateControls()
	local m = ns.live.mirror
	local writer = ns.AmWriter()
	local active = m and (m.state == "open" or m.state == "reroll")
	local decided = m and m.state == "decided"
	buttons.close:SetShown(writer and active)
	buttons.award:SetShown(writer and decided and m.winners[1] ~= nil)
	buttons.cancel:SetShown(writer and (active or decided))
	buttons.greed:SetShown(writer and decided and not m.winners[1] and not m.greed and ns.IsBoE(m.item))
	buttons.writer:SetShown(not writer and IsInGroup() and ns.IsOfficer(ns.PlayerName()))
	tabs.loot:SetShown(ns.loot[1] ~= nil or view == "loot")
end

function ns.RefreshWindow()
	if not frame or not frame:IsShown() then return end
	if view == "session" then
		lines = SessionLines()
	elseif view == "loot" then
		lines = LootLines()
	else
		lines = PityLines()
	end
	offset = math.max(math.min(offset, #lines - ROW_COUNT), 0)
	for key, header in pairs(headers) do header:SetText(HEADERS[view][key] or "") end
	frame.status:SetText(StatusText())
	local m = ns.live.mirror
	if m then
		frame.item:SetText(ns.ItemLink(m.item) .. (m.copies > 1 and (" x" .. m.copies) or "") .. (m.greed and " (greed)" or ""))
		frame.icon:SetTexture(select(10, C_Item.GetItemInfo(m.item)))
		frame.round:SetText(RoundText(m))
	else
		frame.item:SetText("No roll in progress")
		frame.icon:SetTexture(nil)
		frame.round:SetText("")
	end
	local warning = ns.warnings[#ns.warnings]
	frame.warning:SetText(warning and warning.text or "")
	UpdateControls()
	Render()
end

local function SetView(name)
	view, offset = name, 0
	ns.RefreshWindow()
end
ns.SetWindowView = SetView

local function CreateRow(index)
	local row = CreateFrame("Button", nil, frame)
	row:SetSize(WIDTH - 20, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 10, -128 - (index - 1) * ROW_HEIGHT)
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	row.cells = {}
	local x = 0
	for _, column in ipairs(COLUMNS) do
		local cell = Text(row, nil, column.justify)
		cell:SetPoint("LEFT", x, 0)
		cell:SetWidth(column.width - 4)
		row.cells[column.key] = cell
		x = x + column.width
	end
	row.actions = {}
	for a = 1, 2 do
		local action = Button(row, "", ACTION_WIDTH, function(self) if self.func then self.func() end end)
		action:SetHeight(ROW_HEIGHT)
		action:SetPoint("RIGHT", -(a - 1) * (ACTION_WIDTH + 4), 0)
		row.actions[a] = action
	end
	row:SetScript("OnClick", function(self)
		if self.line and self.line.click then self.line.click() end
	end)
	row:SetScript("OnEnter", function(self)
		local line = self.line
		if not line or not (line.link or line.tip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if line.link then GameTooltip:SetHyperlink(line.link) else GameTooltip:SetText(line.tip) end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function Create()
	frame = CreateFrame("Frame", "PitifulLootFrame", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	local position = ns.settings.position
	if position then
		frame:SetPoint(position.point, UIParent, position.point, position.x, position.y)
	else
		frame:SetPoint("CENTER")
	end
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		ns.settings.position = { point = point, x = x, y = y }
	end)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(math.min(offset - delta * 3, #lines - ROW_COUNT), 0)
		Render()
	end)
	table.insert(UISpecialFrames, "PitifulLootFrame")

	local background = frame:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.05, 0.05, 0.07, 0.92)

	local title = Text(frame, "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText("Pitiful Loot")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)

	frame.status = Text(frame)
	frame.status:SetPoint("TOPLEFT", 12, -30)

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(22, 22)
	frame.icon:SetPoint("TOPLEFT", 12, -50)
	frame.item = Text(frame, "GameFontNormal")
	frame.item:SetPoint("LEFT", frame.icon, "RIGHT", 6, 0)
	frame.round = Text(frame, "GameFontNormal", "RIGHT")
	frame.round:SetPoint("TOPRIGHT", -12, -54)

	local tabX = 12
	for _, tab in ipairs({ { "session", "Roll" }, { "loot", "Loot" }, { "pity", "My pity" } }) do
		local button = Button(frame, tab[2], 80, function() SetView(tab[1]) end)
		button:SetPoint("TOPLEFT", tabX, -80)
		tabs[tab[1]] = button
		tabX = tabX + 84
	end

	local x = 10
	for _, column in ipairs(COLUMNS) do
		local header = Text(frame, "GameFontNormalSmall", column.justify)
		header:SetPoint("TOPLEFT", x, -110)
		header:SetWidth(column.width - 4)
		headers[column.key] = header
		x = x + column.width
	end

	for i = 1, ROW_COUNT do rows[i] = CreateRow(i) end

	frame.warning = Text(frame)
	frame.warning:SetPoint("BOTTOMLEFT", 12, 38)
	frame.warning:SetWidth(WIDTH - 24)
	frame.warning:SetTextColor(1, 0.25, 0.25)

	buttons.close = Button(frame, "Close round", 100, function() ns.CloseRound() end)
	buttons.award = Button(frame, "Award", 100, function() ns.Award() end)
	buttons.greed = Button(frame, "Greed roll", 100, function()
		local m = ns.live.mirror
		ns.StartRoll(m.item, m.copies, true)
	end)
	buttons.cancel = Button(frame, "Cancel", 80, function() ns.CancelRoll() end)
	buttons.writer = Button(frame, "Be the writer", 110, function() ns.ClaimWriter() end)
	buttons.close:SetPoint("BOTTOMLEFT", 10, 10)
	buttons.award:SetPoint("BOTTOMLEFT", 10, 10)
	buttons.greed:SetPoint("BOTTOMLEFT", 114, 10)
	buttons.cancel:SetPoint("BOTTOMRIGHT", -10, 10)
	buttons.writer:SetPoint("BOTTOMRIGHT", -94, 10)

	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed < 0.25 then return end
		elapsed = 0
		local m = ns.live.mirror
		if m and m.ends then frame.round:SetText(RoundText(m)) end
	end)
	frame:SetScript("OnShow", ns.RefreshWindow)
	frame:Hide()
end

function ns.ShowWindow()
	if not frame then Create() end
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

-- The rows on show, for tests: each one's cell texts.
function ns.WindowLines()
	return lines
end

for _, name in ipairs({ "SESSION_CHANGED", "LEDGER_CHANGED", "ROSTER_CHANGED", "WARNINGS", "SYNC_CHANGED" }) do
	ns.Listen(name, ns.RefreshWindow)
end
ns.Listen("LOOT_CHANGED", function()
	if ns.loot[1] and ns.AmWriter() then
		view = "loot"
		ns.ShowWindow()
	elseif view == "loot" and not ns.loot[1] then
		view = "session"
	end
	ns.RefreshWindow()
end)
ns.On("GET_ITEM_INFO_RECEIVED", ns.RefreshWindow)
