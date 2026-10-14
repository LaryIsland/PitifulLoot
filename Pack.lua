local _, ns = ...

-- Packing the ledger into bytes (design document 6.5, `Notes/Ledger Format.md`): numbers little-endian, short
-- strings with a length byte, 3-bit cells packed from the lowest bit up, and GUIDs as their last 8 hex digits when a
-- message's GUIDs share one prefix. A message is a tag and its body: 'z' if deflating made it smaller, 'b' if not,
-- escaped either way, as the only byte an addon message can't carry is 0.

local byte, char, concat, floor = string.byte, string.char, table.concat, math.floor

-- Writer -----------------------------------------------------------------------------------------------------------

local Writer = {}
Writer.__index = Writer

function ns.NewWriter()
	return setmetatable({ parts = {} }, Writer)
end

-- A whole number in `size` bytes, little-endian.
function Writer:Int(n, size)
	assert(type(n) == "number" and n >= 0 and n % 1 == 0 and n < 256 ^ size, "can't pack " .. tostring(n))
	for _ = 1, size do
		self.parts[#self.parts + 1] = char(n % 256)
		n = floor(n / 256)
	end
	return self
end
function Writer:U8(n) return self:Int(n, 1) end
function Writer:U16(n) return self:Int(n, 2) end
function Writer:U24(n) return self:Int(n, 3) end
function Writer:U32(n) return self:Int(n, 4) end

function Writer:Bytes(s)
	self.parts[#self.parts + 1] = s
	return self
end

-- A string of up to 255 bytes, after its length.
function Writer:Str8(s)
	assert(#s < 256, "string too long to pack")
	return self:U8(#s):Bytes(s)
end

-- Small numbers (0 to 2^width - 1), `width` bits each, packed from the lowest bit up; the last byte padded with zeros.
function Writer:Bits(values, width)
	local acc, used, size = 0, 0, 2 ^ width
	for _, v in ipairs(values) do
		assert(v >= 0 and v < size and v % 1 == 0, "can't pack " .. tostring(v) .. " in " .. width .. " bits")
		acc = acc + v * 2 ^ used
		used = used + width
		while used >= 8 do
			self.parts[#self.parts + 1] = char(acc % 256)
			acc, used = floor(acc / 256), used - 8
		end
	end
	if used > 0 then self.parts[#self.parts + 1] = char(acc) end
	return self
end

function Writer:Result()
	return concat(self.parts)
end

-- Reader -----------------------------------------------------------------------------------------------------------

local Reader = {}
Reader.__index = Reader

-- Reads bytes from `s`; any read past the end raises, so callers decode inside pcall (ns.Decode).
function ns.NewReader(s)
	return setmetatable({ s = s, pos = 1 }, Reader)
end

function Reader:Take(n)
	local finish = self.pos + n - 1
	if finish > #self.s then error("message ends early", 0) end
	local part = self.s:sub(self.pos, finish)
	self.pos = finish + 1
	return part
end

function Reader:Int(size)
	local part, n = self:Take(size), 0
	for i = size, 1, -1 do n = n * 256 + byte(part, i) end
	return n
end
function Reader:U8() return self:Int(1) end
function Reader:U16() return self:Int(2) end
function Reader:U24() return self:Int(3) end
function Reader:U32() return self:Int(4) end
function Reader:Bytes(n) return self:Take(n) end
function Reader:Str8() return self:Take(self:U8()) end

function Reader:Bits(count, width)
	local values, acc, have, size = {}, 0, 0, 2 ^ width
	for i = 1, count do
		while have < width do
			acc = acc + self:U8() * 2 ^ have
			have = have + 8
		end
		values[i] = acc % size
		acc, have = floor(acc / size), have - width
	end
	return values
end

function Reader:Done()
	return self.pos > #self.s
end

-- GUIDs ------------------------------------------------------------------------------------------------------------

-- The prefix every GUID in a list shares, before their last 8 hex digits ("Player-4621-"), or "" if they don't. The
-- digits are upper case, as the game writes them, so they come back the same.
local TAIL = "^(.*%-)" .. string.rep("[0-9A-F]", 8) .. "$"
function ns.GuidPrefix(guids)
	local prefix
	for _, guid in ipairs(guids) do
		local head = type(guid) == "string" and guid:match(TAIL)
		if not head or (prefix and head ~= prefix) then return "" end
		prefix = head
	end
	return prefix or ""
end

-- A GUID, in the form the message's prefix allows: 4 bytes after a shared prefix, or the whole string.
function Writer:Guid(guid, prefix)
	if prefix ~= "" then return self:U32(tonumber(guid:sub(#prefix + 1), 16)) end
	return self:Str8(guid)
end

function Reader:Guid(prefix)
	if prefix ~= "" then return prefix .. string.format("%08X", self:U32()) end
	return self:Str8()
end

-- Messages ---------------------------------------------------------------------------------------------------------

local function Escape(s)
	return (s:gsub("\1", "\1\1"):gsub("%z", "\1\2"))
end

local function Unescape(s)
	local bad = false
	local out = s:gsub("\1(.?)", function(c)
		if c == "\1" then return "\1" end
		if c == "\2" then return "\0" end
		bad = true
		return ""
	end)
	if bad then return nil end
	return out
end

local DEFLATE = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate

-- A body ready to send: deflated if that makes it smaller, and escaped.
function ns.Wrap(body)
	if C_EncodingUtil and C_EncodingUtil.CompressString then
		local ok, packed = pcall(C_EncodingUtil.CompressString, body, DEFLATE)
		if ok and type(packed) == "string" and #packed < #body then return "z" .. Escape(packed) end
	end
	return "b" .. Escape(body)
end

-- The body of a wrapped message, or nil if it's malformed.
function ns.Unwrap(payload)
	if type(payload) ~= "string" then return nil end
	local tag, body = payload:sub(1, 1), Unescape(payload:sub(2))
	if not body then return nil end
	if tag == "b" then return body end
	if tag ~= "z" or not (C_EncodingUtil and C_EncodingUtil.DecompressString) then return nil end
	local ok, text = pcall(C_EncodingUtil.DecompressString, body, DEFLATE)
	if ok and type(text) == "string" then return text end
	return nil
end

-- Runs a decoder on bytes from another player, which may be anything: its results, or nil if it fails.
---@param decoder function
---@param bytes string
---@return any ...
function ns.Decode(decoder, bytes)
	local results = { pcall(decoder, ns.NewReader(bytes)) }
	if not results[1] then return nil end
	return unpack(results, 2)
end
