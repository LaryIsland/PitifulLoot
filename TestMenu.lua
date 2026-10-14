local _, ns = ...

-- The test menu (/pl test), kept after release as a tutorial: a window of its own that walks through a raid night in
-- the order it happens, on one of two pages. The raider page (the default) is a raider's night: an officer shares the
-- loot, your pity, and rolling as an officer starts each roll. The officer page runs the loot: the raid gathers, an
-- officer takes charge, a boss drops its loot, everyone rolls, and the winners get it. It fakes what other people and
-- the game would do (made-up raiders, a boss's loot, pity from earlier raids, everyone else's rolls, the raider page's
-- officer) through test mode (TestCommands.lua), and each step says what you'd do yourself in the main window. Its
-- text is written for someone who's never used the addon (design document 5.5), and is in Locales, as the TEST_
-- lines; tab and button names in it are the main window's own.

local L = ns.L
local TEXT = {
	TITLE = L.TEST_TITLE,
	INTRO = L.TEST_INTRO,
	NEED_TEST_MODE = L.TEST_NEED_TEST_MODE,

	TEST_MODE = L.TEST_MODE,
	TEST_MODE_TIP = L.TEST_MODE_TIP,
	START_OVER = L.TEST_START_OVER,
	START_OVER_TIP = L.TEST_START_OVER_TIP,
	PAGE_RAIDER = L.TEST_PAGE_RAIDER,
	PAGE_OFFICER = L.TEST_PAGE_OFFICER,
	PAGE_TIP = L.TEST_PAGE_TIP,

	R_SHARE = L.TEST_R_SHARE,
	R_SHARE_TIP = L.TEST_R_SHARE_TIP,
	R_SHARE_BUTTON = L.TEST_R_SHARE_BUTTON,
	R_SHARE_BUTTON_TIP = L.TEST_R_SHARE_BUTTON_TIP,
	R_PITY = L.TEST_R_PITY,
	R_ROLL = L.TEST_R_ROLL,
	R_ROLL_TIP = L.TEST_R_ROLL_TIP,
	R_START_ROLL = L.TEST_R_START_ROLL,
	R_START_ROLL_TIP = L.TEST_R_START_ROLL_TIP,
	R_ROLL_ON = L.TEST_R_ROLL_ON,
	R_ALL_ROLLED = L.TEST_R_ALL_ROLLED,

	RAID = L.TEST_RAID,
	RAID_TIP = L.TEST_RAID_TIP:format(L.TAB_RAID),
	RAID_LINE = L.TEST_RAID_LINE:format(L.RAID_INSPECT_UNKNOWN),
	RAIDERS = L.TEST_RAIDERS,
	RAIDERS_TIP = L.TEST_RAIDERS_TIP,
	FILL = L.TEST_FILL,
	FILL_TIP = L.TEST_FILL_TIP:format(L.TAB_RAID, L.TAB_RAID),
	EMPTY = L.TEST_EMPTY,
	EMPTY_TIP = L.TEST_EMPTY_TIP,
	RAID_FILLED = L.TEST_RAID_FILLED,

	WRITER = L.TEST_WRITER,
	WRITER_TIP = L.TEST_WRITER_TIP:format(L.BUTTON_BE_WRITER),
	WRITER_LINE = L.TEST_WRITER_LINE:format(L.BUTTON_BE_WRITER),

	LOOT = L.TEST_LOOT,
	LOOT_TIP = L.TEST_LOOT_TIP:format(L.TAB_LOOT),
	LOOT_BUTTON = L.TEST_LOOT_BUTTON,
	LOOT_BUTTON_TIP = L.TEST_LOOT_BUTTON_TIP:format(L.TAB_LOOT),

	PITY = L.TEST_PITY,
	PITY_TIP = L.TEST_PITY_TIP,
	GIVE_PITY = L.TEST_GIVE_PITY,
	GIVE_PITY_TIP = L.TEST_GIVE_PITY_TIP:format(L.TAB_LOOT, L.TAB_PITY),
	NEED_LOOT = L.TEST_NEED_LOOT,

	ROLL = L.TEST_ROLL,
	ROLL_TIP = L.TEST_ROLL_TIP:format(L.TAB_ROLL),
	ROLL_LINE = L.TEST_ROLL_LINE:format(L.TAB_LOOT, L.TAB_ROLL),
	MAKE_TIE = L.TEST_MAKE_TIE,
	MAKE_TIE_TIP = L.TEST_MAKE_TIE_TIP:format(L.BUTTON_CLOSE_ROUND),
	NEED_RAIDERS = L.TEST_NEED_RAIDERS,
	NEED_ROLL = L.TEST_NEED_ROLL:format(L.TAB_LOOT),
	FIRST_ROUND = L.TEST_FIRST_ROUND,
	ARRIVING = L.TEST_ARRIVING,
	ALREADY_DONE = L.TEST_ALREADY_DONE,
	PREVIOUS_STEP = L.TEST_PREVIOUS_STEP,
	NEED_ROLLS = L.TEST_NEED_ROLLS,

	AWARD = L.TEST_AWARD,
	AWARD_TIP = L.TEST_AWARD_TIP:format(L.BUTTON_AWARD, L.TAB_LOOT),
	AWARD_LINE = L.TEST_AWARD_LINE:format(L.BUTTON_AWARD, L.TAB_LOOT),

	AS_RAIDER = L.TEST_AS_RAIDER,
	AS_RAIDER_TIP = L.TEST_AS_RAIDER_TIP,
	VIEW_AS_RAIDER = L.TEST_VIEW_AS_RAIDER,
	VIEW_AS_RAIDER_TIP = L.TEST_VIEW_AS_RAIDER_TIP:format(L.TAB_LOOT),
}

local WIDTH = 360
local PADDING = 24 -- from the frame's edge to its contents
local CONTENT = WIDTH - 2 * PADDING
local INDENT = 12 -- a step's line and controls, from its title
local BUTTON_WIDTH, BUTTON_HEIGHT, GAP = 124, 22, 8
local START_OVER_WIDTH = 96 -- narrower, to leave room for the page choice beside it
local PAGE_WIDTH = 100 -- the page choice, between Test Mode and Start Over
local STEP_GAP = 14
local SLIDER_WIDTH = 160
local MAX_RAIDERS, DEFAULT_RAIDERS = 40, 20
-- The main window's metal frame without its portrait (as ButtonFrameTemplate_HidePortrait gives it), over the
-- bronze background of the character screens' panels, which fills the frame below its title bar as the main
-- window's background does.
local BORDER_LAYOUT = "ButtonFrameTemplateNoPortrait"
local BACKGROUND = "heavybronze-frame-background"
local TITLE_BAR = 21 -- the frame's title bar, which the title sits in
local MAIN_GAP = 16 -- between the menu and the main window it sits beside
local SCREEN_MARGIN = 120 -- room left above and below the menu when the screen's too short for all of it
local MIN_BODY = 300 -- the least the menu scrolls within
local CURRENT_ALPHA = 0.05 -- the faint highlight behind the step you're on
local CURRENT_MARGIN = 8 -- how far the highlight reaches round the step
local CHECKMARK = "lootroll-icon-checkmark"
local GREY = { r = 0.486, g = 0.518, b = 0.541 } -- the main window's grey, for each step's description

local menu
-- Every button, checkbox, slider and dropdown: { kind, title, tip, widget, Click, and optionally Label, Tip, Blocked,
-- Checked }.
local controls = {}
local raidSize = DEFAULT_RAIDERS
local hovered -- the region whose tooltip is showing, so it can be redrawn as things change
local pages = {} -- by key, raider then officer: { key, steps (specs), built steps, body, height }
local page = "raider" -- the page on show, raider by default

-- Why a control can't be used right now, if it can't: test mode first, then the step before its own on its page (each
-- step waits for the one before), then its own reason.
local function Blocked(spec)
	if not ns.IsTestMode() and not spec.always then return TEXT.NEED_TEST_MODE end
	local before = spec.step and spec.step > 1 and spec.stepList[spec.step - 1]
	if before and not (before.Done and before.Done()) then return TEXT.PREVIOUS_STEP:format(spec.step - 1) end
	return spec.Blocked and spec.Blocked() or nil
end

local function ShowTip(region)
	local spec = region.spec
	hovered = region
	GameTooltip:SetOwner(region, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, spec.Label and spec.Label() or spec.title)
	local why = spec.widget and Blocked(spec)
	if why then GameTooltip_AddColoredLine(GameTooltip, why, LIGHTBLUE_FONT_COLOR, true) end
	local tip = spec.Tip and spec.Tip() or spec.tip
	local first = true
	for paragraph in (tip .. "\n\n"):gmatch("(.-)\n\n") do
		if not first then GameTooltip_AddNormalLine(GameTooltip, " ") end
		GameTooltip_AddNormalLine(GameTooltip, paragraph, true)
		first = false
	end
	GameTooltip:Show()
end

local function HideTip()
	hovered = nil
	GameTooltip:Hide()
end

local function Hoverable(region, spec)
	region.spec = spec
	region:SetScript("OnEnter", ShowTip)
	region:SetScript("OnLeave", HideTip)
end

-- Controls ------------------------------------------------------------------------------------------------------

local function Button(parent, spec)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(spec.width or BUTTON_WIDTH, BUTTON_HEIGHT)
	button:SetText(spec.Label and spec.Label() or spec.title)
	button:SetMotionScriptsWhileDisabled(true) -- disabled buttons still say why
	button:SetScript("OnClick", function() spec.Click() end)
	spec.widget = button
	Hoverable(button, spec)
	return button
end

local function Checkbox(parent, spec)
	local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	box.Text:SetText(spec.title)
	box.Text:SetFontObject("GameFontHighlight")
	box:SetMotionScriptsWhileDisabled(true)
	box:SetScript("OnClick", function(self) spec.Click(self:GetChecked() and true or false) end)
	spec.widget = box
	Hoverable(box, spec)
	return box
end

-- A label with a slider after it, the slider's value drawn to its right; the label is what's anchored.
local function Slider(parent, spec)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetText(spec.title)
	local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	slider:SetSize(SLIDER_WIDTH, 20)
	slider:SetPoint("LEFT", label, "RIGHT", GAP + 4, 0)
	slider:Init(spec.value, spec.min, spec.max, spec.max - spec.min,
		{ [MinimalSliderWithSteppersMixin.Label.Right] = function(value) return tostring(value) end })
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged,
		function(_, value) spec.Changed(value) end, label)
	spec.widget, spec.label = slider, label
	Hoverable(slider, spec)
	-- Its bar and arrows take the mouse themselves, so they show its tooltip too, and it only goes once the mouse is
	-- off the whole slider (rather than flickering as it crosses from one part to the next).
	local function Leave()
		if not slider:IsMouseOver() then HideTip() end
	end
	slider:SetScript("OnLeave", Leave)
	for _, part in ipairs({ slider:GetChildren() }) do
		part:HookScript("OnEnter", function() ShowTip(slider) end)
		part:HookScript("OnLeave", Leave)
	end
	return label
end

local MAKERS = { button = Button, checkbox = Checkbox, slider = Slider }
-- How tall each kind of control's row is, and where it's drawn in it: a checkbox's box sits inside its 32 pixels.
local ROW_HEIGHTS = { button = BUTTON_HEIGHT, checkbox = 24, slider = 24 }
local OFFSETS = { button = { 0, 0 }, checkbox = { -4, 4 }, slider = { 0, -4 } }

-- The steps -----------------------------------------------------------------------------------------------------

-- The latest loot's items, for the steps that follow it.
local function LatestItems()
	local group = ns.LatestLoot()
	return group and group.items or {}
end

local function AnyItem(test)
	for _, entry in ipairs(LatestItems()) do
		if test(entry) then return true end
	end
	return false
end

local function OpenRoll()
	local m = ns.live.mirror
	return m and (m.state == "open" or m.state == "reroll") and m or nil
end

local function HasRaiders()
	return ns.Test.HasRaiders()
end

-- Whether a roll on any of this loot has been decided.
local function RollFinished()
	return AnyItem(function(entry)
		return entry.status ~= "waiting" and entry.status ~= "rolling" or entry.winners[1] ~= nil
	end)
end

-- Why there's no tie to make yet, if there isn't: it needs a first round with its rolls in, and someone to tie with
-- (with several copies, as many as there are copies).
local function NoTieYet()
	local m = OpenRoll()
	if not HasRaiders() then return TEXT.NEED_RAIDERS end
	if not m then return TEXT.NEED_ROLL end
	if m.state ~= "open" then return TEXT.FIRST_ROUND end
	if ns.Test.RollsArriving() then return TEXT.ARRIVING end
	local rolled = 0
	for _ in pairs(m.rounds[1]) do rolled = rolled + 1 end
	if rolled < m.copies then return TEXT.NEED_ROLLS end
end

local function GivePityButton(key)
	return {
		key = key, kind = "button", title = TEXT.GIVE_PITY, tip = TEXT.GIVE_PITY_TIP,
		Click = function() ns.Test.GivePity() end,
		Blocked = function()
			if not ns.LatestLoot() then return TEXT.NEED_LOOT end
			if ns.Test.GavePity() or ns.Test.GivingPity() then return TEXT.ALREADY_DONE end
		end,
	}
end

-- Each step: what happens at that point in a raid (`tip`, in grey under its title), what to do or look at in the
-- main window (`line`, in white under that, or above it with `lineFirst`), whether it's been done, and its controls,
-- in rows. A control's `key` is for the tests.

-- The raider page: an officer's part (sharing the loot, starting each roll, handing it out) is done for you.
local RAIDER_STEPS = {
	{
		title = TEXT.R_SHARE, tip = TEXT.R_SHARE_TIP, Done = function() return ns.Test.Looted() end,
		rows = {
			{
				{
					key = "share", kind = "button", title = TEXT.R_SHARE_BUTTON, tip = TEXT.R_SHARE_BUTTON_TIP,
					Click = function() ns.Test.ShareLoot() end,
					Blocked = function() return ns.Test.Looted() and TEXT.ALREADY_DONE or nil end,
				},
			},
		},
	},
	{
		title = TEXT.R_PITY, tip = TEXT.PITY_TIP, Done = function() return ns.Test.GavePity() end,
		rows = { { GivePityButton("raiderPity") } },
	},
	{
		title = TEXT.R_ROLL, tip = TEXT.R_ROLL_TIP, Done = RollFinished,
		rows = {
			{
				{
					key = "startRoll", kind = "button", title = TEXT.R_START_ROLL, tip = TEXT.R_START_ROLL_TIP,
					Click = function() ns.Test.StartNextRoll() end,
					Blocked = function()
						local m = ns.live.mirror
						if m and (m.state == "open" or m.state == "reroll" or m.state == "decided") then
							return TEXT.R_ROLL_ON
						end
						if not ns.Test.NextItem() then return TEXT.R_ALL_ROLLED end
					end,
				},
			},
		},
	},
}

-- The officer page: running the loot.
local OFFICER_STEPS = {
	{
		-- Done once the raid's had Inspect Unknown run over it (setting the last role by hand isn't needed).
		title = TEXT.RAID, tip = TEXT.RAID_TIP, line = TEXT.RAID_LINE, Done = function() return ns.Test.Swept() end,
		rows = {
			{
				{
					key = "raiders", kind = "slider", title = TEXT.RAIDERS, tip = TEXT.RAIDERS_TIP,
					value = DEFAULT_RAIDERS, min = ns.Test.RAID_MIN, max = MAX_RAIDERS,
					Changed = function(value) raidSize = value end,
					Blocked = function() return HasRaiders() and TEXT.RAID_FILLED or nil end,
				},
			},
			{
				{
					key = "fill", kind = "button", title = TEXT.FILL,
					Label = function() return HasRaiders() and TEXT.EMPTY or TEXT.FILL end,
					Tip = function() return HasRaiders() and TEXT.EMPTY_TIP or TEXT.FILL_TIP end,
					Click = function()
						if HasRaiders() then ns.Test.EmptyRaid() else ns.Test.FillRaid(raidSize) end
					end,
				},
			},
		},
	},
	{
		-- Done in the main window, with its own button, as in a raid.
		title = TEXT.WRITER, tip = TEXT.WRITER_TIP, line = TEXT.WRITER_LINE, Done = function() return ns.AmWriter() end,
		rows = {},
	},
	{
		title = TEXT.LOOT, tip = TEXT.LOOT_TIP, Done = function() return ns.LatestLoot() ~= nil end,
		rows = {
			{
				{
					key = "loot", kind = "button", title = TEXT.LOOT_BUTTON, tip = TEXT.LOOT_BUTTON_TIP,
					Click = function() ns.Test.Loot() end,
					Blocked = function() return ns.Test.Looted() and TEXT.ALREADY_DONE or nil end,
				},
			},
		},
	},
	{
		title = TEXT.PITY, tip = TEXT.PITY_TIP, Done = function() return ns.Test.GavePity() end,
		rows = { { GivePityButton("pity") } },
	},
	{
		-- The raiders roll by themselves (TestCommands.lua); a tie can be made.
		title = TEXT.ROLL, tip = TEXT.ROLL_TIP, line = TEXT.ROLL_LINE, lineFirst = true,
		Done = RollFinished,
		rows = {
			{
				{
					key = "tie", kind = "button", title = TEXT.MAKE_TIE, tip = TEXT.MAKE_TIE_TIP,
					Click = function() ns.Test.MakeTie() end,
					Blocked = NoTieYet,
				},
			},
		},
	},
	{
		title = TEXT.AWARD, tip = TEXT.AWARD_TIP, line = TEXT.AWARD_LINE,
		Done = function()
			return AnyItem(function(entry) return entry.winners[1] ~= nil or ns.LootDone(entry) end)
		end,
		rows = {},
	},
	{
		title = TEXT.AS_RAIDER, tip = TEXT.AS_RAIDER_TIP, Done = function() return ns.Test.ViewedAsRaider() end,
		rows = {
			{
				{
					key = "raider", kind = "checkbox", title = TEXT.VIEW_AS_RAIDER, tip = TEXT.VIEW_AS_RAIDER_TIP,
					Checked = function() return ns.ViewAsRaider() end,
					Click = function() ns.Test.ToggleRaider() end,
				},
			},
		},
	},
}

-- Keeping it up to date ----------------------------------------------------------------------------------------

local function Refresh()
	if not (menu and menu:IsShown()) then return end
	local on = ns.IsTestMode()
	menu.TestMode:SetChecked(on)
	for _, spec in ipairs(controls) do
		local widget = spec.widget
		local enabled = Blocked(spec) == nil
		widget:SetEnabled(enabled)
		if spec.kind == "button" and spec.Label then widget:SetText(spec.Label()) end
		if spec.kind == "checkbox" then
			widget:SetChecked(spec.Checked and spec.Checked() or false)
			widget.Text:SetFontObject(enabled and "GameFontHighlight" or "GameFontDisable")
		end
		if spec.label then spec.label:SetFontObject(enabled and "GameFontHighlight" or "GameFontDisable") end
	end
	-- On each page, the step you're on, the first not yet done, has a faint highlight behind it.
	for _, each in pairs(pages) do
		local current
		for _, step in ipairs(each.built) do
			local done = on and step.spec.Done ~= nil and step.spec.Done() == true
			step.Title:SetFontObject(on and "GameFontNormal" or "GameFontDisable")
			step.Check:SetShown(done)
			if on and not done and not current then current = step end
			step.Highlight:SetShown(step == current)
		end
	end
	if hovered and GameTooltip:IsOwned(hovered) then ShowTip(hovered) end
end

-- Once every step on either page has been done, the tutorial's finished: the empty Roll tab stops offering it (UI.lua),
-- and the first time the menu's closed after that (or straight away, if it's closed already), chat says how to open it
-- again.
local function TellReopen()
	if not ns.saved.tutorialFinished or ns.saved.tutorialTold then return end
	ns.saved.tutorialTold = true
	ns.Print(L.TEST_MSG_REOPEN)
end

local function CheckFinished()
	if ns.saved.tutorialFinished or not (menu and ns.IsTestMode()) then return end
	for _, each in pairs(pages) do
		local all = true
		for _, step in ipairs(each.built) do
			if not (step.spec.Done and step.spec.Done() == true) then
				all = false
				break
			end
		end
		if all then
			ns.saved.tutorialFinished = true
			if not menu:IsShown() then TellReopen() end
			ns.RefreshWindow()
			return
		end
	end
end

local queued = false
local function RefreshSoon()
	if queued or not (menu and menu:IsShown()) then return end
	queued = true
	C_Timer.After(0, function()
		queued = false
		Refresh()
	end)
end

for _, name in ipairs({ "SESSION_CHANGED", "LOOT_CHANGED", "LEDGER_CHANGED", "ROSTER_CHANGED", "ROLES_CHANGED" }) do
	ns.Listen(name, RefreshSoon)
	ns.Listen(name, CheckFinished)
end
-- Test mode is never on in a raid instance or a raid group (TestCommands.lua turns it off), so Test Mode greys out
-- there.
ns.On("PLAYER_ENTERING_WORLD", RefreshSoon)
ns.On("GROUP_ROSTER_UPDATE", RefreshSoon)

-- The window ------------------------------------------------------------------------------------------------------

-- Beside the main window, following it as it moves, until the menu is dragged away; then it stays where it's put.
local detached = false

local function PlaceMenu()
	local main = ns.Window()
	if detached or not main then return end
	menu:ClearAllPoints()
	menu:SetPoint("TOPRIGHT", main, "TOPLEFT", -MAIN_GAP, 0)
end

-- Dragged by hand, it comes off the main window: anchored where it's drawn, so it doesn't jump as it starts moving.
local function StartDrag(self)
	local left, top = self:GetLeft(), self:GetTop()
	detached = true
	if left and top then
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
	self:StartMoving()
end

-- A page's steps, on a body of their own in the scrolling area, their descriptions in `descColor` (white if nil).
-- Returns the body and how tall it is.
local function BuildPage(scroll, specs, descColor)
	local body = CreateFrame("Frame", nil, scroll)
	body:SetWidth(WIDTH)
	local built = {}
	local y = -10

	-- A step's text: what happens at that point in a raid (grey on the officer page), and what to do in the main window
	-- in white, below it (or above it, for a step with `lineFirst`).
	local function Text(text, color)
		local line = body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		line:SetWidth(CONTENT - INDENT)
		line:SetJustifyH("LEFT")
		if color then line:SetTextColor(color.r, color.g, color.b) end
		line:SetPoint("TOPLEFT", PADDING + INDENT, y)
		line:SetText(text)
		y = y - line:GetStringHeight() - 6
		return line
	end

	for index, spec in ipairs(specs) do
		local step = { spec = spec }
		local top = y
		step.Title = body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		step.Title:SetPoint("TOPLEFT", PADDING, y)
		step.Title:SetText(spec.title)
		step.Check = body:CreateTexture(nil, "ARTWORK")
		step.Check:SetAtlas(CHECKMARK, true)
		step.Check:SetPoint("RIGHT", body, "TOPRIGHT", -PADDING, y - 6)
		y = y - 18
		local function Description()
			if (spec.tip or "") ~= "" then step.Text = Text(spec.tip, descColor) end
		end
		if not spec.lineFirst then Description() end
		if spec.line then step.Line = Text(spec.line) end
		if spec.lineFirst then Description() end
		for _, row in ipairs(spec.rows) do
			local height, previous = 0, nil
			for _, control in ipairs(row) do
				control.step, control.stepList = index, specs
				local region = MAKERS[control.kind](body, control)
				local offset = OFFSETS[control.kind]
				if previous then
					region:SetPoint("LEFT", previous, "RIGHT", GAP + offset[1], 0)
				else
					region:SetPoint("TOPLEFT", PADDING + INDENT + offset[1], y + offset[2])
				end
				previous = control.widget
				height = math.max(height, ROW_HEIGHTS[control.kind])
				controls[#controls + 1] = control
			end
			y = y - height - 6
		end
		step.Highlight = body:CreateTexture(nil, "BACKGROUND")
		step.Highlight:SetColorTexture(1, 1, 1, CURRENT_ALPHA)
		step.Highlight:SetPoint("TOPLEFT", body, "TOPLEFT", PADDING - CURRENT_MARGIN, top + CURRENT_MARGIN / 2)
		step.Highlight:SetPoint("BOTTOMRIGHT", body, "TOPRIGHT", CURRENT_MARGIN - PADDING, y + 6 - CURRENT_MARGIN / 2)
		step.Highlight:Hide()
		y = y - STEP_GAP + 6
		built[#built + 1] = step
	end
	local height = -y + PADDING - STEP_GAP
	body:SetHeight(height)
	return body, height, built
end

-- Shows a page: its steps in the scrolling area, the menu as tall as they are (unless the screen's shorter), and the
-- main window as a raider sees it on the raider page, with the made-up officer as the writer, or as an officer does on
-- the officer page.
local function ShowPage(key)
	page = key
	for name, each in pairs(pages) do each.body:SetShown(name == key) end
	local shown = pages[key]
	menu.Scroll:SetScrollChild(shown.body)
	menu.Scroll:SetVerticalScroll(0)
	local room = (UIParent:GetHeight() or 0) - SCREEN_MARGIN - menu.headerHeight
	if room < MIN_BODY then room = shown.height end
	menu:SetHeight(TITLE_BAR + menu.headerHeight + math.min(shown.height, room) + 4)
	ns.Test.SetRaiderPage(key == "raider")
	Refresh()
end

local function Create()
	menu = CreateFrame("Frame", "PitifulLootTestMenu", UIParent)
	menu:SetWidth(WIDTH)
	menu:SetToplevel(true)
	menu:SetFrameStrata("HIGH")
	menu:SetClampedToScreen(true)
	menu:SetMovable(true)
	menu:SetDontSavePosition(true)
	menu:EnableMouse(true)
	menu:RegisterForDrag("LeftButton")
	menu:SetScript("OnDragStart", StartDrag)
	menu:SetScript("OnDragStop", menu.StopMovingOrSizing)
	menu:SetScript("OnShow", RefreshSoon)
	-- The main window's link to the menu shows only while the menu's closed.
	menu:HookScript("OnShow", function() ns.RefreshWindow() end)
	menu:HookScript("OnHide", function()
		CheckFinished()
		TellReopen()
		ns.RefreshWindow()
	end)
	table.insert(UISpecialFrames, "PitifulLootTestMenu")

	local background = menu:CreateTexture(nil, "BACKGROUND")
	background:SetAtlas(BACKGROUND)
	background:SetPoint("TOPLEFT", 6, -TITLE_BAR) -- where the game's own panels with this frame have theirs
	background:SetPoint("BOTTOMRIGHT", -2, 2)
	local border = CreateFrame("Frame", nil, menu, "NineSlicePanelTemplate")
	border:SetAllPoints()
	border:SetFrameLevel(menu:GetFrameLevel()) -- as the game's frames have it: its art on the frame's own level
	if NineSliceUtil then NineSliceUtil.ApplyLayoutByName(border, BORDER_LAYOUT) end

	local close = CreateFrame("Button", nil, menu, "UIPanelCloseButtonDefaultAnchors")
	menu.CloseButton = close

	-- The title goes in a frame of its own above the border, whose title bar art would cover it otherwise, as the
	-- game's frames do (their TitleContainer).
	local titleBar = CreateFrame("Frame", nil, menu)
	titleBar:SetFrameLevel(border:GetFrameLevel() + 10)
	titleBar:SetPoint("TOPLEFT", 24, -1)
	titleBar:SetPoint("TOPRIGHT", -24, -1)
	titleBar:SetHeight(TITLE_BAR - 1)
	local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -5)
	title:SetText(TEXT.TITLE)
	menu.Title = title

	-- Above the steps, always in view: the intro, then test mode itself, the page, and starting over.
	local y = -TITLE_BAR - 12
	local intro = menu:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	intro:SetWidth(CONTENT)
	intro:SetJustifyH("LEFT")
	intro:SetPoint("TOPLEFT", PADDING, y)
	intro:SetText(TEXT.INTRO)
	y = y - intro:GetStringHeight() - 8
	local testMode = {
		key = "testMode", kind = "checkbox", title = TEXT.TEST_MODE, tip = TEXT.TEST_MODE_TIP, always = true,
		Checked = function() return ns.IsTestMode() end,
		Blocked = function() return ns.TestModeBlockedText() end,
		Click = function(checked) if checked then ns.Test.On() else ns.Test.Off() end end }
	menu.TestMode = Checkbox(menu, testMode)
	menu.TestMode:SetPoint("TOPLEFT", PADDING - 4, y + 4)
	controls[#controls + 1] = testMode
	local startOver = { key = "startOver", kind = "button", title = TEXT.START_OVER, tip = TEXT.START_OVER_TIP,
		width = START_OVER_WIDTH, Click = function() ns.Test.Reset() end }
	Button(menu, startOver):SetPoint("TOPRIGHT", -PADDING, y)
	controls[#controls + 1] = startOver
	-- The page, as the game's own dropdowns are: its tooltip added to, rather than in place of, the dropdown's own.
	local pageChoice = CreateFrame("DropdownButton", nil, menu, "WowStyle1DropdownTemplate")
	pageChoice:SetWidth(PAGE_WIDTH)
	pageChoice:SetPoint("RIGHT", startOver.widget, "LEFT", -GAP, 0)
	pageChoice:SetupMenu(function(_, root)
		root:CreateRadio(TEXT.PAGE_RAIDER, function() return page == "raider" end, function() ShowPage("raider") end)
		root:CreateRadio(TEXT.PAGE_OFFICER, function() return page == "officer" end, function() ShowPage("officer") end)
	end)
	pageChoice.spec = { title = TEXT.PAGE_RAIDER .. " / " .. TEXT.PAGE_OFFICER, tip = TEXT.PAGE_TIP }
	pageChoice:HookScript("OnEnter", ShowTip)
	pageChoice:HookScript("OnLeave", HideTip)
	menu.Page = pageChoice
	y = y - BUTTON_HEIGHT - 10
	menu.headerHeight = -y - TITLE_BAR

	-- The steps scroll, if the screen's too short for them all.
	local scroll = CreateFrame("ScrollFrame", nil, menu, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, y)
	scroll:SetPoint("BOTTOMRIGHT", 0, 4)
	scroll.ScrollBar:SetHideIfUnscrollable(true)
	scroll.ScrollBar:ClearAllPoints()
	scroll.ScrollBar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -8, -6)
	scroll.ScrollBar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -8, 6)
	-- It drags the window, as the rest of the window does.
	scroll:EnableMouse(true)
	scroll:RegisterForDrag("LeftButton")
	scroll:SetScript("OnDragStart", function() StartDrag(menu) end)
	scroll:SetScript("OnDragStop", function() menu:StopMovingOrSizing() end)
	menu.Scroll = scroll

	local pageList = {
		{ key = "raider", steps = RAIDER_STEPS }, -- all its text white: it has no separate "what to do" lines
		{ key = "officer", steps = OFFICER_STEPS, descColor = GREY },
	}
	for _, each in ipairs(pageList) do
		each.body, each.height, each.built = BuildPage(scroll, each.steps, each.descColor)
		pages[each.key] = each
	end
	-- For the tests: every control, each page's steps (the officer page's as Steps), the text, and the page.
	menu.Controls, menu.Text = controls, TEXT
	menu.Steps, menu.RaiderSteps = pages.officer.built, pages.raider.built
	menu.SetPage = ShowPage
	menu.GetPage = function() return page end
	ShowPage(page)
	-- Closing the main window closes the menu too, as every step works through it.
	ns.Window():HookScript("OnHide", function() menu:Hide() end)
end

-- With the main window, which every step refers to.
function ns.ShowTestMenu()
	ns.ShowWindow()
	if not menu then Create() end
	PlaceMenu()
	menu:Show()
	Refresh()
end

function ns.ToggleTestMenu()
	if menu and menu:IsShown() then
		menu:Hide()
	else
		ns.ShowTestMenu()
	end
end

function ns.TestMenu()
	return menu
end
