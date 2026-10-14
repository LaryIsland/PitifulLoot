local _, ns = ...

-- SHA-256 and HMAC-SHA256 for the ledger (design document 6.3): the table's hash, and officers' signatures on
-- players' rows. Plain Lua, as the game has no hashing API. Written against the game's `bit` library using only
-- two-argument band, bor, bxor, lshift and rshift (no rotate, no bnot), and every sum is kept in 0..2^32-1, so it gives
-- the same answers whether the library's results are signed or unsigned.

local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift
local byte, char, rep, concat, format, floor = string.byte, string.char, string.rep, table.concat, string.format, math.floor
local M = 4294967296
local ALL = M - 1

local function rotr(x, n) return bor(rshift(x, n), lshift(x, 32 - n)) % M end

local function be32(s, i)
	local a, b, c, d = byte(s, i, i + 3)
	return ((a * 256 + b) * 256 + c) * 256 + d
end

local function be32s(x)
	x = x % M
	return char(floor(x / 16777216) % 256, floor(x / 65536) % 256, floor(x / 256) % 256, x % 256)
end

local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
local IV = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

local w = {}
local function Block(H, s, i)
	for j = 0, 15 do w[j] = be32(s, i + j * 4) end
	for j = 16, 63 do
		local x, y = w[j - 15], w[j - 2]
		local s0 = bxor(bxor(rotr(x, 7), rotr(x, 18)), rshift(x, 3))
		local s1 = bxor(bxor(rotr(y, 17), rotr(y, 19)), rshift(y, 10))
		w[j] = (w[j - 16] + s0 % M + w[j - 7] + s1 % M) % M
	end
	local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
	for j = 0, 63 do
		local S1 = bxor(bxor(rotr(e, 6), rotr(e, 11)), rotr(e, 25)) % M
		local ch = bxor(band(e, f), band(bxor(e, ALL), g)) % M
		local t1 = (h + S1 + ch + K[j + 1] + w[j]) % M
		local S0 = bxor(bxor(rotr(a, 2), rotr(a, 13)), rotr(a, 22)) % M
		local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c)) % M
		h, g, f, e, d, c, b, a = g, f, e, (d + t1) % M, c, b, a, (t1 + S0 + maj) % M
	end
	H[1], H[2], H[3], H[4] = (H[1] + a) % M, (H[2] + b) % M, (H[3] + c) % M, (H[4] + d) % M
	H[5], H[6], H[7], H[8] = (H[5] + e) % M, (H[6] + f) % M, (H[7] + g) % M, (H[8] + h) % M
end

-- `state` and `done`: carry on from a state that has already taken `done` bytes (HMAC's key blocks, worked out once).
local function Digest(message, state, done)
	local H = { unpack(state or IV) }
	local length = (done or 0) + #message
	local bits = length * 8
	local s = message .. "\128" .. rep("\0", (55 - length) % 64) .. be32s(floor(bits / M)) .. be32s(bits % M)
	for i = 1, #s, 64 do Block(H, s, i) end
	local out = {}
	for i = 1, 8 do out[i] = be32s(H[i]) end
	return concat(out)
end

-- The 32-byte SHA-256 digest of a string.
function ns.SHA256(message)
	return Digest(message)
end

local function KeyBlock(key, pad)
	if #key > 64 then key = Digest(key) end
	local out = {}
	for i = 1, 64 do out[i] = char(bxor(byte(key, i) or 0, pad) % 256) end
	return concat(out)
end

-- A signer for one key: a function giving the 32-byte HMAC-SHA256 of a message. The key's blocks are hashed once.
function ns.HMACSigner(key)
	local inner, outer = { unpack(IV) }, { unpack(IV) }
	Block(inner, KeyBlock(key, 0x36), 1)
	Block(outer, KeyBlock(key, 0x5c), 1)
	return function(message)
		return Digest(Digest(message, inner, 64), outer, 64)
	end
end

function ns.HMACSHA256(key, message)
	return ns.HMACSigner(key)(message)
end

function ns.ToHex(bytes)
	return (bytes:gsub(".", function(c) return format("%02x", byte(c)) end))
end
