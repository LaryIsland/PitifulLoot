local _, ns = ...

-- SHA-256 and HMAC-SHA256 for the ledger (design document 6.3): the table's hash, and officers' signatures on
-- players' rows. Plain Lua, as the game has no hashing API. Written against the game's `bit` library using only band,
-- bor, bxor, lshift and rshift (no rotate, no bnot), with three-argument bxor and bor where the library takes them
-- (Forever's does, as the beta showed: fewer calls), and two-argument ones otherwise. The working values are kept in 0..2^32-1;
-- what comes out of the bit functions (which may be signed) only goes into other bit functions, or into sums that are
-- brought back into range, so it gives the same answers whether the library's results are signed or unsigned. It
-- runs a lot (/pl perf), so the rotations are written out in place and nothing is brought into range twice.

local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift
local byte, char, rep, concat, format, floor = string.byte, string.char, string.rep, table.concat, string.format, math.floor
local M = 4294967296

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
local Block

-- With three-argument bxor and bor.
local function Block3(H, s, i)
	for j = 0, 15 do
		local p, q, r, t = byte(s, i + j * 4, i + j * 4 + 3)
		w[j] = ((p * 256 + q) * 256 + r) * 256 + t
	end
	for j = 16, 63 do
		local x, y = w[j - 15], w[j - 2]
		w[j] = (w[j - 16] + w[j - 7]
			+ bxor(bor(rshift(x, 7), lshift(x, 25)), bor(rshift(x, 18), lshift(x, 14)), rshift(x, 3))
			+ bxor(bor(rshift(y, 17), lshift(y, 15)), bor(rshift(y, 19), lshift(y, 13)), rshift(y, 10))) % M
	end
	local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
	for j = 0, 63 do
		local t1 = h + bxor(bor(rshift(e, 6), lshift(e, 26)), bor(rshift(e, 11), lshift(e, 21)), bor(rshift(e, 25), lshift(e, 7)))
			+ bxor(g, band(e, bxor(f, g))) + K[j + 1] + w[j]
		local t2 = bxor(bor(rshift(a, 2), lshift(a, 30)), bor(rshift(a, 13), lshift(a, 19)), bor(rshift(a, 22), lshift(a, 10)))
			+ bor(band(a, b), band(c, bor(a, b)))
		h, g, f, e, d, c, b, a = g, f, e, (d + t1) % M, c, b, a, (t1 + t2) % M
	end
	H[1], H[2], H[3], H[4] = (H[1] + a) % M, (H[2] + b) % M, (H[3] + c) % M, (H[4] + d) % M
	H[5], H[6], H[7], H[8] = (H[5] + e) % M, (H[6] + f) % M, (H[7] + g) % M, (H[8] + h) % M
end

-- With two-argument calls only.
local function Block2(H, s, i)
	for j = 0, 15 do
		local p, q, r, t = byte(s, i + j * 4, i + j * 4 + 3)
		w[j] = ((p * 256 + q) * 256 + r) * 256 + t
	end
	for j = 16, 63 do
		local x, y = w[j - 15], w[j - 2]
		local s0 = bxor(bxor(bor(rshift(x, 7), lshift(x, 25)), bor(rshift(x, 18), lshift(x, 14))), rshift(x, 3))
		local s1 = bxor(bxor(bor(rshift(y, 17), lshift(y, 15)), bor(rshift(y, 19), lshift(y, 13))), rshift(y, 10))
		w[j] = (w[j - 16] + s0 + w[j - 7] + s1) % M
	end
	local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
	for j = 0, 63 do
		-- Σ1(e), Ch(e, f, g) = g ^ (e & (f ^ g)), Σ0(a), and Maj(a, b, c) = (a & b) | (c & (a | b)).
		local S1 = bxor(bxor(bor(rshift(e, 6), lshift(e, 26)), bor(rshift(e, 11), lshift(e, 21))),
			bor(rshift(e, 25), lshift(e, 7)))
		local t1 = h + S1 + bxor(g, band(e, bxor(f, g))) + K[j + 1] + w[j]
		local S0 = bxor(bxor(bor(rshift(a, 2), lshift(a, 30)), bor(rshift(a, 13), lshift(a, 19))),
			bor(rshift(a, 22), lshift(a, 10)))
		local maj = bor(band(a, b), band(c, bor(a, b)))
		h, g, f, e, d, c, b, a = g, f, e, (d + t1) % M, c, b, a, (t1 + S0 + maj) % M
	end
	H[1], H[2], H[3], H[4] = (H[1] + a) % M, (H[2] + b) % M, (H[3] + c) % M, (H[4] + d) % M
	H[5], H[6], H[7], H[8] = (H[5] + e) % M, (H[6] + f) % M, (H[7] + g) % M, (H[8] + h) % M
end

local function Takes3(f, x, y, z, want)
	local ok, r = pcall(f, x, y, z)
	return ok and r == want
end
Block = (Takes3(bxor, 1, 2, 4, 7) and Takes3(bor, 1, 2, 4, 7)) and Block3 or Block2
ns.CRYPTO_FAST = Block == Block3 -- for the tests and the probe

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
