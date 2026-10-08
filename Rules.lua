local _, ns = ...

-- The rules at a glance, section 2 of the design document.
ns.PITY_STEP = 10
ns.PITY_MAX = 50
ns.OFFSPEC_MODIFIER = -20
ns.ROLL_MIN = 1
ns.ROLL_MAX = 100
ns.LEAVER_DECAY = 10
ns.LEAVER_DECAY_PERIOD = 7 * 24 * 60 * 60

-- What a player adds to their roll on an item: their pity, less the off-spec penalty. Not floored (4.2).
function ns.Bonus(pity, offSpec)
	return pity + (offSpec and ns.OFFSPEC_MODIFIER or 0)
end

-- The number compared between players. The bonus goes on before the clamp at 100 (4.2).
function ns.EffectiveRoll(roll, bonus)
	return math.min(roll + bonus, ns.ROLL_MAX)
end

-- Pity after losing a roll on the item (4.1).
function ns.AddPity(pity)
	return math.min(pity + ns.PITY_STEP, ns.PITY_MAX)
end
