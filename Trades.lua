local _, ns = ...

-- Won items still to be handed over: each copy awarded that its winner hasn't got yet (Loot.lua's handovers). A
-- copy given by master loot is done straight away; the rest are done when a trade with the winner goes through,
-- which either side's client sees and tells the group, so everyone's Loot tab stays up to date. Officers can also
-- mark one done by hand. A looted BoP item can only be traded for a while, so each shows how long is left.
-- An officer holding copies can open a trade with the winner from the Loot tab, and whoever opens a trade between
-- them, the copies go into it. Each side still clicks Trade: the game doesn't let addons accept a trade.
--
--   traded {sid, id}   the copy `id` won in roll `sid` has reached them; from an officer, or from the winner

local LIVE = ns.PREFIX_LIVE
-- How long a looted BoP item can be traded. Assumed to be Retail's two hours; to check in the beta.
ns.TRADE_WINDOW = 2 * 60 * 60
local TRADE_SLOTS = 6 -- the trade window's seventh slot is for an item that won't be traded

local function EachHandover(callback)
	for _, group in ipairs(ns.loot.groups) do
		for _, entry in ipairs(group.items) do
			for _, handover in ipairs(entry.handovers) do
				if callback(handover, entry, group) then return handover end
			end
		end
	end
end

-- The copies still to be handed over, soonest to run out first: { item, id (the winner), sid, from, expires }.
function ns.PendingTrades()
	local list = {}
	EachHandover(function(handover, entry, group)
		if not handover.done then
			list[#list + 1] = {
				item = entry.item, id = handover.id, sid = handover.sid, from = group.from,
				expires = group.time + ns.TRADE_WINDOW,
			}
		end
	end)
	table.sort(list, function(a, b)
		if a.expires ~= b.expires then return a.expires < b.expires end
		if a.item ~= b.item then return a.item < b.item end
		return a.id < b.id
	end)
	return list
end

local function Done(handover, tell)
	handover.done = true
	if tell and IsInGroup() then
		ns.Send(LIVE, "traded", { sid = handover.sid, id = handover.id }, IsInRaid() and "RAID" or "PARTY")
	end
	ns.Fire("LOOT_CHANGED")
end

-- An officer marking a copy as handed over, from the window: the trade wasn't seen, or it ran out of time.
function ns.MarkTraded(sid, id)
	if not ns.IsOfficer(ns.PlayerName()) then return end
	local handover = EachHandover(function(h) return not h.done and h.sid == sid and h.id == id end)
	if handover then Done(handover, true) end
end

ns.Receive(LIVE, "traded", function(d, sender)
	if type(d) ~= "table" or type(d.sid) ~= "string" or type(d.id) ~= "string" then return end
	local member = ns.GroupMember(sender)
	if not ns.IsOfficer(sender) and not (member and member.guid == d.id) then return end
	local handover = EachHandover(function(h) return not h.done and h.sid == d.sid and h.id == d.id end)
	if handover then Done(handover, false) end
end)

-- Trades -------------------------------------------------------------------------------------------------------

-- What each side has put up, read again whenever it changes. When the game says the trade went through, any won
-- item that went to its winner, either way round, is done: the oldest copy still waiting.
local trade
local FILL_DELAY = 0.1 -- seconds between items put in the trade window, so each lands before the next is picked up
local BAGS = NUM_BAG_SLOTS or 4 -- the backpack is bag 0
-- A looted BoP item's tooltip says how long it can still be traded for, as a pattern.
local TRADE_TIME = BIND_TRADE_TIME_REMAINING
	and BIND_TRADE_TIME_REMAINING:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", ".+")

-- Whether the item in a bag slot can still be traded: not bound, or a looted BoP item still in its trade window.
-- Anything the client can't say counts as tradeable, and the game refuses it if not.
local function Tradeable(bag, slot)
	local location = ItemLocation and ItemLocation:CreateFromBagAndSlot(bag, slot)
	if not (location and C_Item.IsBound(location)) or not TRADE_TIME then return true end
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText
		if canaccessvalue(text) and type(text) == "string" and text:find(TRADE_TIME) then return true end
	end
	return false
end

-- A tradeable copy of the item in your bags, other than the slots already `used`: its bag and slot.
local function FindInBags(item, used)
	for bag = 0, BAGS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			if C_Container.GetContainerItemID(bag, slot) == item and not used[bag .. ":" .. slot] and Tradeable(bag, slot) then
				return bag, slot
			end
		end
	end
end

-- Whether you hold a copy of the item to hand over.
function ns.HoldsItem(item)
	return C_Item.GetItemCount(item) > 0
end

-- Puts the won copies you hold for the person you're trading with into the trade window, soonest to run out first,
-- in its free slots. Only officers hand items over, so a member's own copy of the same item is never put up.
local function FillTrade()
	if not trade or not trade.partner or not ns.IsOfficer(ns.PlayerName()) then return end
	local free = {}
	for slot = 1, TRADE_SLOTS do
		if not GetTradePlayerItemLink(slot) then free[#free + 1] = slot end
	end
	-- Copies already up in the trade count towards what's owed.
	local up = {}
	for _, item in ipairs(trade.gave) do up[item] = (up[item] or 0) + 1 end
	local used, moves = {}, {}
	for _, pending in ipairs(ns.PendingTrades()) do
		if pending.id == trade.partner then
			if (up[pending.item] or 0) > 0 then
				up[pending.item] = up[pending.item] - 1
			elseif free[#moves + 1] then
				local bag, slot = FindInBags(pending.item, used)
				if bag then
					used[bag .. ":" .. slot] = true
					moves[#moves + 1] = { bag = bag, slot = slot, item = pending.item, to = free[#moves + 1] }
				end
			end
		end
	end
	local filling = trade
	for i, move in ipairs(moves) do
		C_Timer.After(FILL_DELAY * (i - 1), function()
			if trade ~= filling or filling.closed or GetTradePlayerItemLink(move.to) then return end
			ClearCursor()
			C_Container.PickupContainerItem(move.bag, move.slot)
			ClickTradeButton(move.to)
			if CursorHasItem() then
				ClearCursor()
				ns.Print(ns.L.MSG_TRADE_FAILED:format(ns.ItemLink(move.item)))
			end
		end)
	end
end

-- Opens a trade with a winner from the Loot tab, which puts in what you hold for them once it's open.
-- The winner can be anyone in your group, or whoever you're targeting.
function ns.OfferTrade(id)
	local member = ns.GroupMember(id)
	local unit = member and member.unit or (UnitGUID("target") == id and "target") or nil
	if not unit then return ns.Print(ns.L.MSG_TRADE_NOT_IN_RAID:format(ns.ColoredName(id))) end
	if trade and not trade.closed and trade.partner == id then return FillTrade() end
	if not CheckInteractDistance(unit, 2) then
		return ns.Print(ns.L.MSG_TRADE_TOO_FAR:format(ns.ColoredName(id)))
	end
	InitiateTrade(unit)
end

local function Oldest(item, id)
	local found, foundTime
	EachHandover(function(handover, entry, group)
		if not handover.done and entry.item == item and handover.id == id and (not found or group.time < foundTime) then
			found, foundTime = handover, group.time
		end
	end)
	return found
end

local function ReadTrade()
	if not trade then return end
	trade.gave, trade.got = {}, {}
	for slot = 1, TRADE_SLOTS do
		trade.gave[#trade.gave + 1] = ns.ItemID(GetTradePlayerItemLink(slot))
		trade.got[#trade.got + 1] = ns.ItemID(GetTradeTargetItemLink(slot))
	end
end

ns.On("TRADE_SHOW", function()
	local partner = UnitGUID("NPC")
	trade = { partner = canaccessvalue(partner) and partner or nil, gave = {}, got = {} }
	ReadTrade()
	FillTrade()
end)
-- The window closes before the game says whether the trade went through, so what was in it is kept until then.
ns.On("TRADE_CLOSED", function()
	if trade then trade.closed = true end
end)
ns.On("TRADE_PLAYER_ITEM_CHANGED", ReadTrade)
ns.On("TRADE_TARGET_ITEM_CHANGED", ReadTrade)
ns.On("TRADE_ACCEPT_UPDATE", ReadTrade)

ns.On("UI_INFO_MESSAGE", function(_, message)
	if not trade or message ~= ERR_TRADE_COMPLETE then return end
	local done = trade
	trade = nil
	for _, item in ipairs(done.gave) do
		local handover = done.partner and Oldest(item, done.partner)
		if handover then Done(handover, true) end
	end
	local me = UnitGUID("player")
	for _, item in ipairs(done.got) do
		local handover = Oldest(item, me)
		if handover then Done(handover, true) end
	end
end)
