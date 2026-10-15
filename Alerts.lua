local _, ns = ...
local L = ns.L

-- Telling you a roll's waiting for you: a sound, and the game's taskbar icon flashing (which it only does while you're
-- tabbed out), each an option. They go off as a roll you can take part in starts, or a reroll you're tied in, with the
-- window opening on it. Not for a reroll auto-roll takes at once, nor for a roll you've just started yourself as the
-- writer (one your queue starts still counts).
--
-- The sound is the ready check's by default, or none, or any sound another addon shares through LibSharedMedia-3.0
-- (by its name, the rollSound option being true for the ready check's and false for none).

local media = LibStub("LibSharedMedia-3.0", true)

-- The sounds to pick from, for the Options tab: none, the ready check's, then the shared ones by name. LibSharedMedia
-- has a "None" of its own, which is left out for ours.
function ns.RollSounds()
	local choices = { { false, L.OPT_SOUND_NONE }, { true, L.OPT_SOUND_READY_CHECK } }
	for _, name in ipairs(media and media:List(media.MediaType.SOUND) or {}) do
		if name ~= "None" then choices[#choices + 1] = { name, name } end
	end
	return choices
end

-- On the Master channel, as the game's own ready check is, so it's heard with sound effects turned off. A shared sound
-- whose addon has gone plays the ready check's instead, so the alert isn't lost.
local function PlayRollSound()
	local sound = ns.settings.rollSound
	if not sound then return end
	local file = type(sound) == "string" and media and media:Fetch(media.MediaType.SOUND, sound, true)
	if file then
		PlaySoundFile(file, "Master")
	elseif SOUNDKIT and SOUNDKIT.READY_CHECK then
		PlaySound(SOUNDKIT.READY_CHECK, "Master")
	end
end

local function Alert(kind)
	if (kind ~= "open" and kind ~= "reroll") or not ns.CanRoll() then return end
	if kind == "reroll" and (ns.settings.autoRoll or ns.AUTO_ROLL.OFF) >= ns.AUTO_ROLL.REROLLS then return end
	if kind == "open" and ns.AmWriter() and not ns.QueueStarting() then return end
	PlayRollSound()
	if ns.settings.rollFlash then FlashClientIcon() end
end

ns.Listen("ROLL_EVENT", Alert)

-- Picking a sound plays it, to hear what it is.
ns.Listen("SETTINGS_CHANGED", function(key)
	if key == "rollSound" then PlayRollSound() end
end)
