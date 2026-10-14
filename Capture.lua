local addonName, ns = ...

-- TEMPORARY, with test mode: a record of everything the addon sees and does, saved to PitifulLootCapture so problems
-- found in game can be read back and replayed in the harness. Like the swing timer's captures, the last 10 are kept
-- and a capture stops when it's full. A capture runs whenever test mode is on.

local MAX_CAPTURES = 10
local MAX_RECORDS = 5000
local MAX_DEPTH = 6

local capture, started

-- A copy that can be saved: secret values, functions and frames are described rather than kept.
local function Saveable(value, depth)
	if issecretvalue and issecretvalue(value) then return "<secret>" end
	local kind = type(value)
	if kind == "table" then
		if value.GetObjectType then return "<frame>" end
		if depth >= MAX_DEPTH then return "<table>" end
		local copy = {}
		for k, v in pairs(value) do
			if type(k) == "string" or type(k) == "number" then copy[k] = Saveable(v, depth + 1) end
		end
		return copy
	elseif kind == "function" or kind == "userdata" or kind == "thread" then
		return "<" .. kind .. ">"
	end
	return value
end

function ns.Capture(kind, ...)
	if not capture then return end
	local record = { kind = kind, time = math.floor((GetTime() - started) * 1000 + 0.5) / 1000, server = GetServerTime() }
	local count = select("#", ...)
	if count > 0 then
		record.args = {}
		for i = 1, count do record.args[i] = Saveable((select(i, ...)), 0) end
	end
	table.insert(capture.records, record)
	if #capture.records >= MAX_RECORDS then
		capture = nil
		ns.Print(("The test capture is full (%d records) and has stopped. It's saved when you log out or /reload; /pl test capture starts another."):format(MAX_RECORDS))
	end
end

function ns.CaptureCount()
	return capture and #capture.records
end

function ns.StopCapture()
	capture = nil
end

function ns.StartCapture()
	PitifulLootCapture = PitifulLootCapture or {}
	capture = {
		date = date("%Y-%m-%d %H:%M"),
		version = C_AddOns.GetAddOnMetadata(addonName, "Version"),
		character = ns.PlayerName(),
		records = {},
	}
	started = GetTime()
	table.insert(PitifulLootCapture, capture)
	while #PitifulLootCapture > MAX_CAPTURES do table.remove(PitifulLootCapture, 1) end

	-- Where things stood when the capture began, so a replay can start from the same place.
	local members = {}
	for _, member in ipairs(ns.GroupMembers()) do
		members[#members + 1] = { guid = member.guid, name = member.name, class = member.class }
	end
	ns.Capture("start", {
		me = UnitGUID("player"), guild = ns.guild, group = members, inRaid = IsInRaid(),
		ledger = ns.ledger and ns.ledger.data, settings = ns.settings, writer = ns.live and ns.live.writer,
	})
end

ns.On("ADDON_LOADED", function(name)
	if name == addonName and ns.IsTestMode() then ns.StartCapture() end
end)
