local _, ns = ...

-- Every line of text players see, in one place for reviewing and translating. Code uses the names on the left
-- (L.TAB_ROLL); a name with no text here shows as itself, with an error, so a typo is easy to spot.
--
-- This is British English. It's registered as enUS because the game has no English locale but enUS (British
-- clients report enUS too) and AceLocale treats enGB as enUS. A translation goes in a file of its own, loaded after
-- this one in the TOC, that starts:
--   local L = LibStub("AceLocale-3.0"):NewLocale("PitifulLoot", "deDE")
--   if not L then return end
-- and sets the lines it translates; anything it leaves out stays in English.
--
-- Placeholders: %s is text (a name, an item, another line), %d a whole number. Keep them, in the same order.

local L = LibStub("AceLocale-3.0"):NewLocale("PitifulLoot", "enUS", true)

-- The window: tabs, header and footer -----------------------------------------------------------------------------

L["TAB_ROLL"] = "Roll"
L["TAB_PITY"] = "My Pity"
L["TAB_LOOT"] = "Loot"
L["TAB_RAID"] = "Raid"
L["TAB_OPTIONS"] = "Options"

-- Each tab's text when it has nothing to list.
L["EMPTY_SESSION"] = "No roll in progress."
L["EMPTY_PITY"] = "You haven't built up any pity yet."
L["EMPTY_LOOT"] = "Loot a boss as master looter to list its items here."
L["EMPTY_LOOT_HIDDEN"] = "None of the loot is for you."
L["EMPTY_RAID"] = "Join a raid to see its roles."
L["EMPTY_NOT_ROLLED_YET"] = "No one has rolled yet."
L["EMPTY_NO_ONE_ROLLED"] = "No one rolled."

-- Under the item being rolled for: how its roll stands, then the time left.
L["STATE_OPEN"] = "Rolling"
L["STATE_REROLL"] = "Reroll"
L["STATE_DECIDED"] = "Decided"
L["STATE_CANCELLED"] = "Cancelled"
L["STATE_AWARDED"] = "Awarded"
L["STATE_DISENCHANTED"] = "Disenchanted" -- also on the Loot tab
L["STATE_KEPT"] = "Kept to sell" -- also on the Loot tab
L["ROUND_ROLL_NOW"] = "Roll now"
L["ROUND_REROLL_N"] = "Reroll %d"
L["ROUND_FOR_SLOTS"] = "%s for %d" -- a reroll, and how many copies it's for
L["ROUND_NO_ROLLS"] = "No rolls"
L["ROUND_AWARDED"] = "Awarded (revision %d)"
L["ROUND_TIME_LEFT"] = "%s: %ds left"
L["HEADER_GREED"] = " (greed)" -- after the item's name
L["HEADER_WAITING"] = "Waiting for %s to start a roll."

-- The footer, and /pl status.
L["FOOTER_REVISION"] = "Rev %d"
L["FOOTER_REVISION_BY"] = "Rev %d by %s" -- the officer who recorded it
L["FOOTER_REVISION_SYNCING"] = "Rev %d, syncing"
L["FOOTER_NO_LEDGER"] = "No guild ledger"
L["WRITER"] = "Writer: %s"
L["WRITER_NONE"] = "Writer: none"

-- The writer's buttons along the bottom.
L["BUTTON_CLOSE_ROUND"] = "Close round"
L["BUTTON_AWARD"] = "Award"
L["BUTTON_GREED_ROLL"] = "Greed roll"
L["BUTTON_KEEP"] = "Keep to sell"
L["BUTTON_DISENCHANT"] = "Disenchant"
L["BUTTON_BE_WRITER"] = "Be the writer"
L["BUTTON_CANCEL"] = "Cancel"

-- The warning sign top right, when something didn't match what this client saw.
L["ALERT_TITLE"] = "Something didn't match"
L["HINT_DISMISS"] = "Click to dismiss."

-- The resize handle under the window.
L["RESIZE_TITLE"] = "Resize"
L["HINT_RESIZE_DRAG"] = "Drag to make the window taller or shorter."
L["HINT_RESIZE_RESET"] = "Right-click to reset its size."

-- The Roll tab -----------------------------------------------------------------------------------------------------

-- A row's details, in three columns.
L["ROW_ROLLED"] = "Rolled %d"
L["ROW_REROLLED"] = "Rerolled %d"
L["ROW_PITY"] = "Pity +%d"
L["ROW_OFFSPEC"] = "Off-spec %d"
L["ROW_OFFSPEC_GUESSED"] = "Off-spec %d?" -- from a fallback role, while theirs is unknown
L["ROW_ROLE_UNKNOWN"] = "Role unknown"
-- Under a row's total, and in its tooltip.
L["ROW_NOT_ROLLED"] = "Hasn't rolled"
L["ROW_NOT_REROLLED"] = "Hasn't rerolled"
L["ROW_PASSED"] = "Passed"
L["ROW_CHANCE"] = "%s chance" -- a percentage
L["ROW_TIP_OFFSPEC"] = "%d (off-spec)"
L["ROW_TIP_BEFORE_TIE"] = "Before the tie: %s"
L["ROW_TIP_PASSED"] = "You passed. /roll still counts if you change your mind."
L["HINT_COUNT_MAIN"] = "Click to count this roll as main-spec."
L["HINT_COUNT_OFF"] = "Click to count this roll as off-spec."

-- Your own row while you can roll.
L["PROMPT_ROLL"] = "Click to roll"
L["PROMPT_REROLL"] = "Click to reroll"
L["PROMPT_AUTO_ROLL"] = "Auto-roll in %ds"
L["ROLL_TIP_TITLE"] = "Roll"
L["ROLL_TIP"] = "Does a /roll 1-100 for you."
L["PASS_TIP_ROLL"] = "You won't roll for this item. Typing /roll still counts if you change your mind."
L["PASS_TIP_REROLL"] = "You won't reroll, so you lose the tie. You still gain pity."

-- Your own row when you can't take part in the roll: why, then the same in its tooltip.
L["CANT_ROLL_NOT_TIED"] = "Only the tied players reroll"
L["CANT_ROLL_WON"] = "You've won this item"
L["CANT_ROLL_CLASS"] = "You can't use this item"
L["CANT_ROLL_NOT_TIED_TIP"] = "You can't roll: only the tied players reroll."
L["CANT_ROLL_WON_TIP"] = "You can't roll: you've won this item before."
L["CANT_ROLL_CLASS_TIP"] = "You can't roll: you can't use this item."

-- A /roll of yours the writer didn't count, on your own row and in its tooltip; the reason is one of the WHY_ lines
-- at the end of this file.
L["REFUSED_DETAIL"] = "Didn't count: %s"
L["REFUSED"] = "Your roll of %d didn't count: %s."
L["REFUSED_RANGE_HINT"] = "Only a roll from 1 to 100 counts: click to roll, or type /roll."

-- The Loot tab -----------------------------------------------------------------------------------------------------

L["LOOT_GROUP"] = "Loot %d" -- loot with no boss to name it by
L["LOOT_COPIES"] = "%d copies"
L["LOOT_BOE"] = "Binds on Equip"
L["LOOT_ROLLING"] = "Rolling now"
L["LOOT_WON_BY"] = "Won by %s"
L["LOOT_AWARDED_TO"] = "Awarded to %s"
L["LOOT_PART_AWARDED"] = "%d of %d awarded: %s"
L["LOOT_AWARDED_REST_KEPT"] = "Awarded to %s, the rest kept to sell"
L["LOOT_AWARDED_REST_DISENCHANTED"] = "Awarded to %s, the rest disenchanted"
L["LOOT_NO_ONE_ROLLED"] = "No one rolled"
L["LOOT_WON_NOTE"] = "You've won this"
L["LOOT_PITY_NOTE"] = "Your pity"
L["HINT_START_ROLL"] = "Left-click to start a roll."
L["HINT_GREED_OR_ROLES"] = "Right-click for a greed roll, or to set its roles."
L["HINT_GREED"] = "Right-click to start a greed roll."
L["HINT_SET_ROLES"] = "Right-click to set its roles." -- also on the item at the top of the window

-- An officer's right-click menu on an item.
L["MENU_GREED_ROLL"] = "Start a greed roll"
L["MENU_ROLES"] = "Roles"

-- Won items awaiting trade, at the top of the Loot tab.
L["TRADE_HEADER"] = "Awaiting trade (%d)"
L["TRADE_FOR"] = "For %s"
L["TRADE_FROM"] = "From %s"
L["TRADE_NOTE"] = "to trade" -- under the time left
L["TRADE_EXPIRED"] = "Expired"
L["TIME_MINUTES"] = "%dm"
L["TIME_HOURS"] = "%dh %02dm"
L["HINT_TRADE"] = "Left-click to trade it to %s."
L["HINT_TRADE_DONE"] = "Right-click if it's been handed over."
L["HINT_TRADE_CLEAR"] = "Right-click to clear it."

-- The My Pity tab --------------------------------------------------------------------------------------------------

L["PITY_WON"] = "Won"
L["PITY_ODDS"] = "%d%% vs 0 pity" -- %% is a percent sign
L["PITY_OTHER_RAID"] = "Other" -- items with no recorded raid, such as ones set by hand
L["PITY_UNKNOWN_BOSS"] = "Unknown boss"

-- The Raid tab -----------------------------------------------------------------------------------------------------

L["ROLE_TANK"] = "Tank"
L["ROLE_HEALER"] = "Healer"
L["ROLE_DAMAGER"] = "Damage"
L["RAID_GROUP"] = "Group %d"
L["RAID_INSPECTING"] = "Inspecting talents" -- dots that count up follow it
L["RAID_AUTOMATIC"] = "Automatic (%s)" -- the role it would give, as an icon
L["RAID_INSPECT_UNKNOWN"] = "Inspect Unknown"
L["RAID_INSPECT_UNKNOWN_TIP"] = "Inspect raiders with unknown roles."
L["RAID_INSPECTING_BUTTON"] = "Inspecting..."
L["HINT_INSPECT"] = "Left-click to update role from talents"
L["HINT_SET_ROLE"] = "Right-click to set their role."
-- Where a raider's role came from, when it isn't certain.
L["ROLE_SOURCE_OFFICER"] = "Set by %s"
L["ROLE_SOURCE_RAID"] = "Set in Blizzard's role menu"
L["ROLE_SOURCE_KNOWN"] = "Last known role"
-- Why a raider's role is unknown, in red under their name. \n starts a new line in the tooltip (it's a space in chat).
L["REASON_FAR"] = "Too far away."
L["REASON_NOREPLY"] = "Inspect got no response. Try again."
L["REASON_UNREADABLE"] = "Talents couldn't be read. Try again."
L["REASON_AMBIGUOUS"] = "Talents are ambiguous.\nPlease set role."
L["REASON_NOCAPSTONE"] = "Talents don't reveal their spec.\nPlease set role."
-- In chat, after inspecting.
L["TALENTS_SAY_TANK"] = "%s's talents say tank."
L["TALENTS_SAY_HEALER"] = "%s's talents say healer."
L["TALENTS_SAY_DAMAGER"] = "%s's talents say damage."
L["SWEEP_DONE"] = "Inspected %s: %s found." -- the two lines below
L["SWEEP_RAIDER"] = "%d raider"
L["SWEEP_RAIDERS"] = "%d raiders"
L["SWEEP_ROLE"] = "%d role"
L["SWEEP_ROLES"] = "%d roles"

-- The Options tab --------------------------------------------------------------------------------------------------

L["OPT_SECONDS"] = "%d sec"
L["OPT_SECTION_ANNOUNCEMENTS"] = "Announcements"
L["OPT_SECTION_RUNNING_ROLLS"] = "Running Rolls"
L["OPT_SECTION_ROLLING"] = "Rolling"
L["OPT_SECTION_WINDOW"] = "Window"
L["OPT_SECTION_PROFILE"] = "Profile"

L["OPT_ANNOUNCE"] = "Announce in Raid Chat"
L["OPT_ANNOUNCE_TIP"] = "As the writer, post roll starts, ties, and results, to raid chat."
L["OPT_WHISPER_REFUSALS"] = "Whisper Refused Rolls"
L["OPT_WHISPER_REFUSALS_TIP"] = "As the writer, whisper players without the addon when their roll didn't count, once per roll."
L["OPT_RAID_WARNING"] = "Use Raid Warnings"
L["OPT_RAID_WARNING_TIP"] = "As the writer, post roll starts, ties, and results, as raid warnings instead of in raid chat. You must be the raid leader or on assist."
L["OPT_ROLL_TIME"] = "Roll Time"
L["OPT_ROLL_TIME_TIP"] = "How long players have to /roll when a roll starts."
L["OPT_REROLL_TIME"] = "Reroll Time"
L["OPT_REROLL_TIME_TIP"] = "How long tied players have to /roll again."
L["OPT_LOOT_QUALITY"] = "Loot Quality"
L["OPT_LOOT_QUALITY_TIP"] = "The lowest item quality listed in the loot tab for rolling."
L["OPT_QUALITY_UNCOMMON"] = "Uncommon"
L["OPT_QUALITY_RARE"] = "Rare"
L["OPT_QUALITY_EPIC"] = "Epic"
L["OPT_QUALITY_LEGENDARY"] = "Legendary"
L["OPT_AUTO_AWARD"] = "Award Automatically"
L["OPT_AUTO_AWARD_TIP"] = "As the writer, award rolls the instant they're decided, without clicking Award."
L["OPT_AUTO_ROLL"] = "Auto-roll"
L["OPT_AUTO_ROLL_TIP"] = "Rolls for you.\nRerolls only: only rolls when you're tied.\nEvery roll: rolls on everything you're eligible for, unless you pass first."
L["OPT_AUTO_ROLL_OFF"] = "Off"
L["OPT_AUTO_ROLL_REROLLS"] = "Rerolls only"
L["OPT_AUTO_ROLL_ALL"] = "Every roll"
L["OPT_AUTO_SHOW"] = "Show When I Can Roll"
L["OPT_AUTO_SHOW_TIP"] = "Open the addon on the Roll tab when a roll starts that you're eligible for."
L["OPT_AUTO_SHOW_LOOT"] = "Show New Loot"
L["OPT_AUTO_SHOW_LOOT_TIP"] = "Open the addon on the Loot tab when a boss's loot is added."
L["OPT_HIDE_UNROLLABLE"] = "Hide Loot I Can't Roll On"
L["OPT_HIDE_UNROLLABLE_TIP"] = "Hide items you can't roll on from the Loot tab."
L["OPT_PITY_BY_BOSS"] = "Group My Pity by Boss"
L["OPT_PITY_BY_BOSS_TIP"] = "On the My Pity tab, group items by the boss that drops them."
L["OPT_HIDE_WON"] = "Hide Won Items"
L["OPT_HIDE_WON_TIP"] = "Hide items you've won from the My Pity tab."
L["OPT_MINIMAP_BUTTON"] = "Minimap Button"
L["OPT_MINIMAP_BUTTON_TIP"] = "Show a minimap button: left-click opens the addon, right-click for options."
L["OPT_SHOW_RAID_TAB"] = "Show the Raid Tab"
L["OPT_SHOW_RAID_TAB_TIP"] = "Show the Raid tab, with every raider's role."
L["OPT_TOOLTIP_HINTS"] = "Show Click Hints in Tooltips"
L["OPT_TOOLTIP_HINTS_TIP"] = "End this addon's tooltips with green hint lines saying what clicks will do."
L["OPT_OFFICER"] = "Officer options" -- the tick box bottom right
L["OPT_OFFICER_TIP"] = "Show the options for running rolls. The raid and loot tabs always show in full for officers."

-- Profiles: the option, its menu and its dialogs.
L["OPT_PROFILE"] = "This Character"
L["OPT_PROFILE_TITLE"] = "Profile"
L["OPT_PROFILE_TIP"] = "The current options are kept in a profile."
L["PROFILE_NEW"] = "New Profile"
L["PROFILE_COPY"] = "Copy From"
L["PROFILE_RESET"] = "Reset to Defaults"
L["PROFILE_DELETE"] = "Delete"
L["PROFILE_NEW_DIALOG"] = "Name the new profile."
L["PROFILE_COPY_DIALOG"] = "Copy the options from %s into %s?"
L["PROFILE_RESET_DIALOG"] = "Reset every option in %s to its default?"
L["PROFILE_DELETE_DIALOG"] = "Delete the profile %s?"
L["PROFILE_EXISTS"] = "There's already a profile called %s."

-- The minimap button -----------------------------------------------------------------------------------------------

L["HINT_MINIMAP_LEFT"] = "Left-click to show or hide the addon."
L["HINT_MINIMAP_RIGHT"] = "Right-click for options."
L["HINT_MINIMAP_DRAG"] = "Drag to move."

-- Slash commands (/pl help). The command words themselves stay in English. --------------------------------------

L["HELP_TOGGLE"] = "/pl - show or hide the addon"
L["HELP_OPTIONS"] = "/pl options - open the Options tab"
L["HELP_WRITER"] = "/pl writer - run loot rolls for this raid (officers)"
L["HELP_ROLL"] = "/pl roll <item> [copies] [greed] - start a roll"
L["HELP_ROUND"] = "/pl close | cancel | award - end the current round, drop the roll, or record and hand out the item"
L["HELP_DISENCHANT"] = "/pl disenchant - mark a BoP item no one rolled on to be disenchanted"
L["HELP_SELL"] = "/pl sell - mark a BoE no one greed-rolled on to be kept and sold"
L["HELP_PASS"] = "/pl pass - pass on the roll in progress"
L["HELP_OS"] = "/pl os <name> - flip a roll's off-spec flag before the first round closes"
L["HELP_PITY"] = "/pl pity [name] - list pity"
L["HELP_LEAVE"] = "/pl leave <name> | rejoin <name> - record a player leaving or rejoining the guild by hand (officers)"
L["HELP_ADJUST"] = "/pl adjust <name> <item> <+/-pity|won> [unlock] - correct pity, record a win, or lift a lockout (officers)"
L["HELP_RESYNC"] = "/pl resync <officer> - replace your ledger with an officer's"
L["HELP_STATUS"] = "/pl status - ledger revision, writer and warnings"
L["HELP_LOG"] = "/pl log [count] - the latest events in your full log, and your ledger checked against it"
L["USAGE_ROLL"] = "/pl roll <item link or ID> [copies] [greed]"
L["USAGE_ADJUST"] = "/pl adjust <name> <item> <+/-pity|won> [unlock]"

-- Messages in your own chat window ---------------------------------------------------------------------------------

-- Commands.
L["MSG_OFFICERS_ONLY"] = "Only officers can do that."
L["MSG_PLAYER_NOT_FOUND"] = "Can't find %s in your raid or guild."
L["MSG_RECORDED"] = "Recorded as revision %d."
L["MSG_NOT_RECORDED"] = "Not recorded: %s." -- a reason from the ledger, below
L["MSG_PITY_WON"] = "%s won"
L["MSG_PITY_NONE"] = "%s has no pity yet."
L["MSG_PITY_STEPS"] = "Pity changes go in steps of 10, from -50 to +50."
L["MSG_ADJUST_ALREADY_WON"] = "%s has already won %s."
L["MSG_ADJUST_WON"] = "%s has won %s; add unlock to give them pity on it again."
L["MSG_STATUS"] = "%s ledger: revision %d (%s)."
L["MSG_STATUS_SYNCING"] = "%s ledger: revision %d (%s), syncing."
L["MSG_STATUS_NO_LEDGER"] = "No guild ledger loaded."

-- Running rolls.
L["MSG_NEED_GROUP"] = "You need to be in a group."
L["MSG_WRITER_OFFICERS"] = "Only officers can be the writer."
L["MSG_LEDGER_NOT_LOADED"] = "Your guild's ledger hasn't loaded yet."
L["MSG_WRITER_ONLY"] = "Only the writer can start a roll. An officer becomes the writer with /pl writer."
L["MSG_WAIT_SYNC"] = "Wait until your ledger has finished syncing."
L["MSG_FINISH_ROLL"] = "Award or cancel the current roll first."
L["MSG_NOTHING_TO_AWARD"] = "There's no decided roll to award."
L["MSG_ONLY_SELL"] = "Only a BoE no one greed-rolled on can be kept to sell."
L["MSG_ONLY_DISENCHANT"] = "Only an item no one rolled on can be disenchanted."
L["MSG_ROLES_FAILED"] = "The roles couldn't be recorded: %s."
L["MSG_WRITER_TAKEN"] = "%s has taken over as the writer."
L["MSG_WRITER_LEFT"] = "%s, the writer, has left the raid. Another officer can take over with /pl writer."
L["MSG_GIVE"] = "Give %s to %s." -- items master loot couldn't hand out

-- Trades and the guild.
L["MSG_TRADE_FAILED"] = "%s couldn't be put in the trade."
L["MSG_TRADE_NOT_IN_RAID"] = "%s isn't in your raid or targeted."
L["MSG_TRADE_TOO_FAR"] = "%s is too far away to trade with."
L["MSG_LEFT_GUILD"] = "%s left the guild; recorded as revision %d."
L["MSG_REJOINED_GUILD"] = "%s rejoined the guild; recorded as revision %d."

-- Syncing the ledger.
L["MSG_NOT_OFFICER"] = "%s isn't an officer in your guild."
L["MSG_FETCHING"] = "Fetching the ledger from %s."
L["MSG_SYNCED"] = "Your ledger now matches %s's (revision %d)."

-- The full log (/pl log): one line per event, after its date.
L["LOG_EMPTY"] = "Your full log is empty."
L["LOG_HEADER"] = "Your full log (the latest %d of %d events):"
L["LOG_NOBODY"] = "nobody"
L["LOG_ROLL"] = "%s: won by %s, lost by %s (%s's roll)" -- item, winners, losers, the writer
L["LOG_GREED"] = "%s: won on greed by %s (%s's roll)"
L["LOG_RESULT"] = "%s: won by %s, lost by %s (recorded by %s, in a raid you weren't in)"
L["LOG_ADJUST"] = "%s's pity on %s: %s (by %s)" -- player, item, the change (+20), the officer
L["LOG_WON"] = "%s recorded as having won %s (by %s)" -- player, item, the officer
L["LOG_UNLOCK"] = "%s's lockout on %s lifted, then %s (by %s)"
L["LOG_LEAVE"] = "%s left the guild (recorded by %s)"
L["LOG_REJOIN"] = "%s rejoined the guild (recorded by %s)"
L["LOG_ITEMROLES"] = "%s's roles set by %s"
L["LOG_ROLE"] = "%s's last known role: %s (by %s)"
L["LOG_ROLE_UNKNOWN"] = "unknown"
L["LOG_MERGE"] = "%s merged %d changes (revision %d)"
L["LOG_BASE"] = "Took %s's table (revision %d)"
L["LOG_ROW"] = "%s sent your pity: %s" -- the officer, then items and their pity
L["LOG_WONBEFORE"] = "%s reported that %s had already won %s"
L["LOG_DOUBLEWIN"] = "%s won %s twice"
-- Checking the ledger against the log, after the events.
L["LOG_CHECK_SINCE"] = "Checking from %s, when you last took another officer's table."
L["LOG_CHECK_NONE"] = "Nothing in your log to check your ledger against yet."
L["LOG_CHECK_OK"] = "Your ledger matches your log (%d items checked)."
L["LOG_CHECK_BAD"] = "%s, %s: your ledger has %s, but your log says %s (as of %s)." -- player, item, ledger, log, date
L["LOG_CHECK_RESYNC"] = "Checking %s's table against your log, for anything your old table had that this one doesn't:"
L["LOG_CHECK_RESYNC_HINT"] = "If your log is right, /pl adjust puts it back: +/- pity, or won for a win."
L["LOG_CHECK_HINT"] = "A difference can be a change your log never saw, from a raid you weren't in or one that hasn't reached you yet."

-- Warnings: in red in chat, and in the warning sign's tooltip. -----------------------------------------------------

L["WARN_DIVERGED"] = "Your ledger differs from %s's at revision %d. If theirs is right, /pl resync %s replaces yours."
L["WARN_AWARD_FAILED"] = "The award couldn't be recorded: %s."
L["WARN_UNSEEN_ROLL"] = "%s: the writer counted a roll of %d that you didn't see."
L["WARN_DIFFERENT_ROLL"] = "%s: the writer counted a roll of %d, but you saw %d."
L["WARN_UNCOUNTED"] = "%s rolled %d, but the writer didn't count it."
L["WARN_PITY"] = "%s: the writer used pity %d, but your ledger (revision %d) says %d."
L["WARN_WINNERS"] = "The winners the writer announced don't match the rolls."
L["WARN_DOUBLE_WIN"] = "%s won %s again in %s's roll, after already winning it in another raid. Either their game missed that award (no addon, or it closed before saving), or their addon was tampered with."
L["WARN_WON_BEFORE"] = "%s reported that %s had already won %s before %s's roll gave it to them. Not proven: a reporter's addon could have been tampered with, though several reports make it likelier."
L["WARN_WON_BEFORE_SEEN"] = "First report: %s's roll on %s." -- the officer who ran the earlier roll, and its date
L["LIST_MORE"] = "%s and %d more" -- a few names, then how many others
L["WARN_ENTRY"] = "Revision %d, recorded by %s, doesn't match the roll you watched."

-- Why the ledger turned an entry down, after "Not recorded:", "was refused:" and the like. -------------------------

L["LEDGER_NO_GUILD"] = "you're not in a guild"
L["LEDGER_NOT_OFFICER"] = "only officers can record entries"
L["LEDGER_SYNCING"] = "your ledger is still syncing"
-- Why a roll doesn't count: in a recorded award, and on your own row on the Roll tab.
L["WHY_LATE"] = "too late"
L["WHY_RANGE"] = "rolled %d-%d"
L["WHY_RAID"] = "not in the raid"
L["WHY_WON"] = "already won this item"
L["WHY_CANTUSE"] = "can't use this item"
L["WHY_OVER"] = "the roll is over"
L["WHY_BADROLL"] = "not a roll from 1 to 100"
L["WHY_ALREADY"] = "already rolled"
L["WHY_NOTREROLL"] = "not in the reroll"
L["WHY_NOPITY"] = "no pity given"

ns.L = LibStub("AceLocale-3.0"):GetLocale("PitifulLoot")

-- Raid chat and whispers -------------------------------------------------------------------------------------------

-- What the writer posts to the group, and whispers to players without the addon. Everyone in the raid reads these,
-- so they stay in English whatever language the writer's game is in; a Chat Language option can offer translations
-- of this table once there are some.
local CHAT = {
	-- A roll starting, and its last call.
	ROLL_START = "%s: /roll now (%ds)",
	GREED_ROLL_START = "Greed roll for %s: /roll now (%ds)",
	COPIES = "%s (%d copies)", -- the item, when there's more than one
	CLOSING = "%d seconds left to /roll for %s.",
	-- Ties.
	WINS = "%s wins %s.", -- one winner of some of the copies, before a tie for the rest
	WIN = "%s win %s.", -- several winners
	LAST_COPY = "the last copy of %s",
	LAST_COPIES = "the last %d copies of %s",
	TIE = "Tie for %s between %s: /roll again (%ds).",
	-- Results, and each winner's breakdown ("Lary: 62 + 50 pity - 20 off-spec = 92").
	GOES_TO = "%s goes to %s.",
	NO_ONE_ROLLED = "No one rolled for %s.",
	BREAKDOWN_PITY = "%s + %d pity",
	BREAKDOWN_OFFSPEC = "%s - %d off-spec",
	BREAKDOWN_MAX = "%s (max)",
	BREAKDOWN_REROLL = "%s (reroll)",
	-- What happens to it.
	SOLD = "%s will be sold.",
	DISENCHANTED = "%s will be disenchanted.",
	CANCELLED = "The roll for %s was cancelled.",
	-- The writer.
	RUNNING_ROLLS = "%s is running loot rolls.",
	TAKEN_OVER = "%s has taken over the roll for %s.",
	-- The whisper to a player without the addon whose roll didn't count, and why.
	REFUSED = "Your roll for %s didn't count: %s.",
	REFUSED_RANGE_HINT = "Type /roll 100 instead.",
	WHY_LATE = "too late",
	WHY_RANGE = "rolled %d-%d",
	WHY_RAID = "not in the raid",
	WHY_WON = "already won this item",
	WHY_CANTUSE = "can't use this item",
	WHY_OVER = "the roll is over",
	WHY_BADROLL = "not a roll from 1 to 100",
	WHY_ALREADY = "already rolled",
	WHY_NOTREROLL = "not in the reroll",
	WHY_NOPITY = "no pity given",
}

-- A name with no text shows as itself, with an error, as for L.
ns.CHAT = setmetatable(CHAT, {
	__index = function(self, key)
		rawset(self, key, key)
		geterrorhandler()("PitifulLoot: missing chat text '" .. tostring(key) .. "'")
		return key
	end,
})
