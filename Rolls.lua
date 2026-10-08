local _, ns = ...

-- Turns the client's roll message format ("%s rolls %d (%d-%d)" on enUS) into a pattern, so it works in any locale
-- that keeps the arguments in order.
local function PatternFromFormat(format)
	local pattern = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
	pattern = pattern:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
	return "^" .. pattern .. "$"
end

local rollPattern

-- Reads a /roll system message. Returns the roller's name, the roll, and the range, or nil if it isn't one.
function ns.ParseRoll(message)
	rollPattern = rollPattern or PatternFromFormat(RANDOM_ROLL_RESULT)
	local name, roll, low, high = message:match(rollPattern)
	if not name then return nil end
	return name, tonumber(roll), tonumber(low), tonumber(high)
end
