local _, ns = ...

-- Addon messages, through AceComm, which splits them to fit and paces them with ChatThrottleLib. Live roll traffic
-- and ledger sync use separate prefixes, and live messages go out first, so a long sync never holds up a roll.
-- Messages are tables: serialized, then deflated if that makes them smaller and escaped (Pack.lua's ns.Wrap).

ns.PREFIX_LIVE = "PitLoot"
ns.PREFIX_SYNC = "PitLootSync"

local PRIORITY = { [ns.PREFIX_LIVE] = "ALERT", [ns.PREFIX_SYNC] = "BULK" }

local comm = LibStub("AceComm-3.0"):Embed({})
local handlers = {}

local function Encode(kind, data)
	return ns.Wrap(ns.Serialize({ k = kind, d = data }))
end

local function Decode(payload)
	local body = ns.Unwrap(payload)
	if not body then return nil end
	local message = ns.Deserialize(body)
	if type(message) ~= "table" or type(message.k) ~= "string" then return nil end
	return message.k, message.d
end

-- Sends `data` to handlers registered for `kind` on other clients.
function ns.Send(prefix, kind, data, channel, target)
	if prefix == ns.PREFIX_SYNC and ns.IsTestMode() then return end -- a test ledger never leaves this client
	if ns.TestIsPrivate() then return end -- nor anything else in test mode, unless someone in the group is trusted
	ns.Capture("send", prefix, kind, data, channel, target)
	comm:SendCommMessage(prefix, Encode(kind, data), channel, target, PRIORITY[prefix])
end

-- handler(data, sender, channel). Messages a client sends to a channel come back to it; those aren't passed on.
function ns.Receive(prefix, kind, handler)
	handlers[prefix][kind] = handler
end

-- callback(sender) for every message on the prefix from another client, whatever it is.
local watchers = {}
function ns.OnMessage(prefix, callback)
	watchers[prefix] = watchers[prefix] or {}
	table.insert(watchers[prefix], callback)
end

local function OnMessage(prefix, payload, channel, sender)
	if ns.IsMe(sender) or (prefix == ns.PREFIX_SYNC and ns.IsTestMode()) then return end
	local kind, data = Decode(payload)
	ns.Capture("receive", prefix, kind, data, sender, channel)
	if kind then
		for _, callback in ipairs(watchers[prefix] or {}) do callback(sender) end
	end
	local handler = kind and handlers[prefix][kind]
	if not handler then return end
	local ok, err = xpcall(handler, ns.WithStack, data, sender, channel)
	if not ok then ns.ReportError(prefix .. " " .. kind, err) end
end

for prefix in pairs(PRIORITY) do
	handlers[prefix] = {}
	comm:RegisterComm(prefix, OnMessage)
end
