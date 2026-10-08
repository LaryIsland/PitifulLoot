local _, ns = ...

-- Table keys are written sorted (numbers first, then strings) and strings are length-prefixed, so equal tables give
-- identical text on every client whatever order their keys were added in.
local function KeyLess(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then return ta == "number" end
	return a < b
end

local function Write(value, out)
	local t = type(value)
	if t == "table" then
		local keys = {}
		for k in pairs(value) do keys[#keys + 1] = k end
		table.sort(keys, KeyLess)
		out[#out + 1] = "{"
		for _, k in ipairs(keys) do
			Write(k, out)
			Write(value[k], out)
		end
		out[#out + 1] = "}"
	elseif t == "string" then
		out[#out + 1] = "s" .. #value .. ":" .. value
	elseif t == "number" then
		-- %d is a 32-bit long on some builds; %.0f is exact for every integer a double holds.
		out[#out + 1] = string.format(value % 1 == 0 and "n%.0f;" or "n%.17g;", value)
	elseif t == "boolean" then
		out[#out + 1] = value and "T" or "F"
	else
		error("can't serialize a " .. t)
	end
end

function ns.Serialize(value)
	local out = {}
	Write(value, out)
	return table.concat(out)
end

local function Read(text, pos)
	local tag = text:sub(pos, pos)
	if tag == "{" then
		local t = {}
		pos = pos + 1
		while text:sub(pos, pos) ~= "}" do
			if pos > #text then error("unterminated table") end
			local key, value
			key, pos = Read(text, pos)
			value, pos = Read(text, pos)
			t[key] = value
		end
		return t, pos + 1
	elseif tag == "s" then
		local length, start = text:match("^(%d+):()", pos + 1)
		if not length then error("bad string") end
		local finish = start + tonumber(length) - 1
		if finish > #text then error("string runs past the end") end
		return text:sub(start, finish), finish + 1
	elseif tag == "n" then
		local digits, after = text:match("^([^;]+);()", pos + 1)
		local number = tonumber(digits)
		if not number then error("bad number") end
		return number, after
	elseif tag == "T" then
		return true, pos + 1
	elseif tag == "F" then
		return false, pos + 1
	end
	error("unexpected " .. (tag == "" and "end" or tag))
end

-- Reads text written by Serialize, which may have come from another player. Returns nil and an error if it's
-- malformed, never raises.
function ns.Deserialize(text)
	if type(text) ~= "string" then return nil, "not text" end
	local ok, value, pos = pcall(Read, text, 1)
	if not ok then return nil, value end
	if pos ~= #text + 1 then return nil, "trailing data" end
	return value
end

-- Two polynomial hashes modulo primes near 2^31, as 16 hex digits. Only arithmetic, so it's exact in doubles and
-- needs no bit library. It's for spotting copies that differ (6.3), not for security: authenticity comes from every
-- client checking results against the rolls it saw.
local M1, M2 = 2147483647, 2147483629

function ns.Hash(text)
	local h1, h2 = 0, 0
	for i = 1, #text do
		local b = text:byte(i) + 1
		h1 = (h1 * 257 + b) % M1
		h2 = (h2 * 263 + b) % M2
	end
	return string.format("%08x%08x", h1, h2)
end
