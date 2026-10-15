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
--
-- Names of things in the addon players see or click (tabs, buttons, options, commands) go in braces, {like this}:
-- they're shown in a colour of their own. A placeholder for one goes in braces too: {%s}. Raid chat (CHAT, at the
-- end) can't carry colours, so it has none.

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
-- Under the Roll tab's empty text when you're not in a raid: a link to the test menu, and its tooltip's hint.
L["EMPTY_TRY_TEST"] = "New here?"
L["EMPTY_TRY_TEST_BUTTON"] = "Try the Tutorial"

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
L["FOOTER_REVISION_LONG"] = "Revision %d"
L["FOOTER_REVISION_BY_LONG"] = "Revision %d by %s" -- the officer who recorded it
L["FOOTER_REVISION_SYNCING_LONG"] = "Revision %d, syncing"
L["FOOTER_REVISION_BY"] = "Rev %d by %s" -- beside the roll's buttons
L["FOOTER_REVISION_SYNCING"] = "Rev %d, syncing"
L["FOOTER_NO_LEDGER"] = "No guild ledger"
L["WRITER_NONE"] = "No Writer"
L["WRITER"] = "Writer: %s" -- in chat, from /pl status; the window shows just the name

-- The writer's buttons along the bottom.
L["BUTTON_CLOSE_ROUND"] = "Close round"
L["BUTTON_AWARD"] = "Award"
L["BUTTON_GREED_ROLL"] = "Greed roll"
L["BUTTON_KEEP"] = "Keep to sell"
L["BUTTON_DISENCHANT"] = "Disenchant"
L["BUTTON_BE_WRITER"] = "Be the writer"
L["BUTTON_CLEAR_QUEUE"] = "Clear Queue"
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
L["CANT_ROLL_NOT_FOR_CLASS"] = "This item isn't for your class"
L["CANT_ROLL_NOT_TIED_TIP"] = "You can't roll: only the tied players reroll."
L["CANT_ROLL_WON_TIP"] = "You can't roll: you've won this item before."
L["CANT_ROLL_CLASS_TIP"] = "You can't roll: you can't use this item."
L["CANT_ROLL_NOT_FOR_CLASS_TIP"] = "You can't roll: this item's stats aren't for your class."

-- A /roll of yours the writer didn't count, on your own row and in its tooltip; the reason is one of the WHY_ lines
-- at the end of this file.
L["REFUSED_DETAIL"] = "Didn't count: %s"
L["REFUSED"] = "Your roll of %d didn't count: %s."
L["REFUSED_RANGE_ONLY"] = "Only a roll from 1 to 100 counts." -- after a roll in another range, under the reason
L["REFUSED_RANGE_HINT"] = "Click to roll, or type /roll" -- the click hint under it

-- The Loot tab -----------------------------------------------------------------------------------------------------

L["LOOT_GROUP"] = "Loot %d" -- loot with no boss to name it by
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
L["HINT_START_GREED"] = "Left-click to start a greed roll."
-- While a roll is under way, or the queue's next is about to start, the writer's click queues an item instead.
L["HINT_ENQUEUE"] = "Click to queue."
L["HINT_DEQUEUE"] = "Click to dequeue."
L["HINT_GREED_MENU"] = "Right-click to start a greed roll." -- a BoE, for the writer
L["HINT_GREED_OR_ROLES"] = "Right-click to start a greed roll or set roles." -- a BoE, for a writer who sets roles
L["HINT_SET_ROLES"] = "Right-click to set roles." -- also on the item at the top of the window

-- An officer's right-click menu on an item.
L["MENU_GREED_ROLL"] = "Start a greed roll"
L["MENU_ROLES"] = "Roles"
-- The writer's dice on a boss's loot.
L["ROLL_ALL"] = "Roll all"
L["HINT_ROLL_ALL"] = "Click to queue all items from this boss."

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
L["ROLE_SOURCE_GEAR"] = "Found from talents/gear"
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
L["GEAR_SAYS_TANK"] = "%s's talents leave tank or damage, and their gear says tank."
L["GEAR_SAYS_DAMAGER"] = "%s's talents leave tank or damage, and their gear says damage."
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
L["OPT_CHAT_LANGUAGE"] = "Chat Language"
L["OPT_CHAT_LANGUAGE_TIP"] = "The language for raid chat and whispers."
L["OPT_WHISPER_REFUSALS"] = "Whisper Refused Rolls"
L["OPT_WHISPER_REFUSALS_TIP"] = "As the writer, whisper players without the addon when their roll didn't count, once per roll."
L["OPT_RAID_WARNING"] = "Use Raid Warnings"
L["OPT_RAID_WARNING_TIP"] = "As the writer, post roll starts, ties, and results, as raid warnings instead of in raid chat. You must be the raid leader or on assist."
L["OPT_ROLL_TIME"] = "Roll Time"
L["OPT_ROLL_TIME_TIP"] = "How long players have to /roll when a roll starts."
L["OPT_REROLL_TIME"] = "Reroll Time"
L["OPT_REROLL_TIME_TIP"] = "How long tied players have to /roll again."
L["OPT_LOOT_QUALITY"] = "Loot Quality"
L["OPT_LOOT_QUALITY_TIP"] = "The lowest item quality listed in the {loot} tab for rolling."
L["OPT_QUALITY_UNCOMMON"] = "Uncommon"
L["OPT_QUALITY_RARE"] = "Rare"
L["OPT_QUALITY_EPIC"] = "Epic"
L["OPT_QUALITY_LEGENDARY"] = "Legendary"
L["OPT_AUTO_AWARD"] = "Auto-award"
L["OPT_AUTO_AWARD_TIP"] = "As the writer, award items instantly.\n{Awards only}: awards won items.\n{Everything}: also disenchants, and greed-rolls when no one needed."
L["OPT_AUTO_AWARD_OFF"] = "Off"
L["OPT_AUTO_AWARD_AWARDS"] = "Awards only"
L["OPT_AUTO_AWARD_ALL"] = "Everything"
L["OPT_AUTO_ROLL"] = "Auto-roll"
L["OPT_AUTO_ROLL_TIP"] = "Rolls for you.\n{Rerolls only}: only rolls when you're tied.\n{Every roll}: rolls on everything you're eligible for, unless you pass first."
L["OPT_AUTO_ROLL_OFF"] = "Off"
L["OPT_AUTO_ROLL_REROLLS"] = "Rerolls only"
L["OPT_AUTO_ROLL_ALL"] = "Every roll"
L["OPT_FONT"] = "Font"
L["OPT_FONT_TIP"] = "The font for all of the addon's text."
L["OPT_AUTO_SHOW"] = "Show When I Can Roll"
L["OPT_AUTO_SHOW_TIP"] = "Open the addon on the {Roll} tab when a roll starts that you're eligible for."
L["OPT_AUTO_SHOW_LOOT"] = "Show New Loot"
L["OPT_AUTO_SHOW_LOOT_TIP"] = "Open the addon on the {Loot} tab when a boss's loot is added."
L["OPT_HIDE_UNROLLABLE"] = "Hide Loot I Can't Roll On"
L["OPT_HIDE_UNROLLABLE_TIP"] = "Hide items you can't roll on from the {Loot} tab."
L["OPT_PITY_BY_BOSS"] = "Group My Pity by Boss"
L["OPT_PITY_BY_BOSS_TIP"] = "On the {My Pity} tab, group items by the boss that drops them."
L["OPT_HIDE_WON"] = "Hide Won Items"
L["OPT_HIDE_WON_TIP"] = "Hide items you've won from the {My Pity} tab."
L["OPT_MINIMAP_BUTTON"] = "Minimap Button"
L["OPT_MINIMAP_BUTTON_TIP"] = "Show a minimap button: left-click opens the addon, right-click for options."
L["OPT_SHOW_RAID_TAB"] = "Show the Raid Tab"
L["OPT_SHOW_RAID_TAB_TIP"] = "Show the {Raid} tab, with every raider's role."
L["OPT_TOOLTIP_HINTS"] = "Show Click Hints in Tooltips"
L["OPT_TOOLTIP_HINTS_TIP"] = "End this addon's tooltips with green hint lines saying what clicks will do."
L["OPT_OFFICER"] = "Officer options" -- the tick box bottom right
L["OPT_OFFICER_TIP"] = "Show the options for running rolls. The {raid} and {loot} tabs always show in full for officers."

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

-- The test menu (/pl test): a raid night on your own, a step at a time, for learning how the addon works -----------

-- Its text is for someone who's never used the addon. \n\n starts a new paragraph. The %s in it
-- are the main window's tab and button names, from the lines above (TAB_ROLL, BUTTON_AWARD and so on).
L["TEST_TITLE"] = "Tutorial"
-- After the main window's title while test mode is on, in red.
L["TEST_WINDOW_TITLE"] = "(test mode)"
L["TEST_WINDOW_TITLE_AS_RAIDER"] = "(test mode, as a raider)"
L["TEST_INTRO"] = "Walk through a raid on your own, step by step."
-- Why a button or box can't be used yet, in light blue at the top of its tooltip.
L["TEST_NEED_TEST_MODE"] = "Turn on {Test Mode} first, it's at the top."
L["TEST_IN_RAID"] = "Test mode can't be used inside a raid."
L["TEST_IN_RAID_GROUP"] = "Test mode can't be used in a raid group."
L["TEST_RAID_FILLED"] = "{Empty the raid} to change this."
L["TEST_NEED_LOOT"] = "{Loot a boss} first, in step 3."
L["TEST_NEED_RAIDERS"] = "{Fill the raid} first, in step 1."
L["TEST_NEED_ROLL"] = "Start a roll first: click an item on the {%s} tab." -- the Loot tab
L["TEST_FIRST_ROUND"] = "Ties are made in the first round."
L["TEST_ARRIVING"] = "Wait for the raiders' rolls to come in."
L["TEST_NEED_ROLLS"] = "Wait for someone to roll first."
L["TEST_PREVIOUS_STEP"] = "Finish step %d first." -- the step before this one
L["TEST_ALREADY_DONE"] = "Done. {Start Over} to do it again." -- a step's button that's done its job
-- Above the steps.
L["TEST_MODE"] = "Test Mode"
L["TEST_MODE_TIP"] = "Test mode lets you try the addon without touching real data or needing a group.\n\nAll messages are shown only to you."
L["TEST_START_OVER"] = "Start Over"
L["TEST_START_OVER_TIP"] = "Clears all test data."
-- Which page of steps to show: taking part as a raider, or running the loot as an officer.
L["TEST_PAGE_RAIDER"] = "Raider"
L["TEST_PAGE_OFFICER"] = "Officer"
L["TEST_PAGE_TIP"] = "{Raider}: rolling for loot in a raid.\n{Officer}: running the loot."
-- The raider page: three steps, an officer's part done for you.
L["TEST_R_SHARE"] = "1. Loot Is Shared"
L["TEST_R_SHARE_TIP"] = "An officer loots the boss and shares the items with the raid."
L["TEST_R_SHARE_BUTTON"] = "Share Loot"
L["TEST_R_SHARE_BUTTON_TIP"] = "Simulates an officer sharing a boss's loot."
L["TEST_R_PITY"] = "2. Your Pity" -- with TEST_PITY_TIP under it, and the Give Test Pity button
L["TEST_R_ROLL"] = "3. Roll"
L["TEST_R_ROLL_TIP"] = "An officer starts a roll on each item in turn, and the other raiders roll too."
L["TEST_R_START_ROLL"] = "Start a Roll"
L["TEST_R_START_ROLL_TIP"] = "Simulates an officer starting a roll on the next item."
L["TEST_R_ROLL_ON"] = "Wait for this roll to finish."
L["TEST_R_ALL_ROLLED"] = "Every item's been rolled for. {Start Over} to go again."
-- The officer page.
-- Step 1. Each step has a title, a description under it in grey saying what happens at that point in a real raid,
-- and some have a line in white saying what to do or look at in the main window (above the description in step 5).
L["TEST_RAID"] = "1. Gather the Raid"
L["TEST_RAID_TIP"] = "Roles come from talents, or an officer setting them.\nRolling on an item as off-spec incurs a -20 roll penalty."
L["TEST_RAID_LINE"] = "Fill the raid, then click {%s}." -- RAID_INSPECT_UNKNOWN
L["TEST_RAIDERS"] = "Raiders"
L["TEST_RAIDERS_TIP"] = "How many people are in the test raid."
L["TEST_FILL"] = "Fill the Raid"
L["TEST_FILL_TIP"] = "Adds test raiders to the {%s} tab.\n\nSome have roles the addon doesn't know yet, shown with a question mark." -- the Raid tab
L["TEST_EMPTY"] = "Empty the Raid"
L["TEST_EMPTY_TIP"] = "Clears the test raiders."
-- Step 2.
L["TEST_WRITER"] = "2. Take Charge of the Loot"
L["TEST_WRITER_TIP"] = "One officer runs the loot rolls for the whole raid: the writer."
L["TEST_WRITER_LINE"] = "Click {%s} at the bottom of the main window." -- BUTTON_BE_WRITER
-- Step 3.
L["TEST_LOOT"] = "3. Loot the Boss"
L["TEST_LOOT_TIP"] = "When you check a boss's loot, the list is shared with the raid."
L["TEST_LOOT_BUTTON"] = "Loot a Boss"
L["TEST_LOOT_BUTTON_TIP"] = "Simulates a boss dropping items." -- the Loot tab
-- Step 4.
L["TEST_PITY"] = "4. Pity From Earlier Raids"
L["TEST_PITY_TIP"] = "When you lose an item roll:\nYour next roll on that item gets +10, up to +50."
L["TEST_GIVE_PITY"] = "Give Test Pity"
L["TEST_GIVE_PITY_TIP"] = "Gives you and some of the raiders pity on this boss's items, as if you'd lost rolls on them in earlier raids."
-- Step 5.
L["TEST_ROLL"] = "5. Roll"
L["TEST_ROLL_TIP"] = "Players without the addon can still type /roll"
L["TEST_ROLL_LINE"] = "Open the {%s} tab, then click an item to start a roll." -- the Loot tab
L["TEST_MAKE_TIE"] = "Make a Tie"
L["TEST_MAKE_TIE_TIP"] = "A raider rolls the same total as the highest, so you can see what happens in a tie."
-- Step 6.
L["TEST_AWARD"] = "6. Hand Out the Loot"
L["TEST_AWARD_TIP"] = "" -- BUTTON_AWARD
L["TEST_AWARD_LINE"] = "Once a roll is decided, the writer clicks {%s}. The winner gets the item, and everyone else who rolled gains +10 pity on it." -- BUTTON_AWARD, the Loot tab
-- Step 7.
L["TEST_AS_RAIDER"] = "7. See It as a Raider"
L["TEST_AS_RAIDER_TIP"] = "Raiders see the rolls, the loot and their own pity, but none of the officers' controls."
L["TEST_VIEW_AS_RAIDER"] = "View as a Raider"
L["TEST_VIEW_AS_RAIDER_TIP"] = "Shows the main window the way raiders without officer powers see it."
-- In chat, as the steps are done.
L["TEST_MSG_ON"] = "Test mode on. Raid messages are shown only to you."
L["TEST_MSG_OFF"] = "Test mode off"
L["TEST_MSG_OFF_IN_RAID"] = "Test mode has turned off, as you're inside a raid."
L["TEST_MSG_OFF_IN_RAID_GROUP"] = "Test mode has turned off, as you're in a raid group."
L["TEST_MSG_NEED_TEST_MODE"] = "Turn on test mode first, at the top of the test menu ({/pl test})."
L["TEST_MSG_RESET"] = "The test data has been cleared."
L["TEST_MSG_RAID_FILLED"] = "%d raiders are on the {%s} tab." -- how many, the Raid tab
L["TEST_MSG_RAID_FILLED_UNKNOWN"] = "%d raiders are on the {%s} tab, the first with each kind of unknown role." -- how many, the Raid tab
L["TEST_MSG_RAID_GONE"] = "Cleared the test raiders."
L["TEST_MSG_NO_GEAR"] = "Wear some gear first: the test loot is made from items you're wearing."
L["TEST_MSG_NEED_LOOT"] = "{Loot a boss} first."
L["TEST_MSG_PITY_GIVEN"] = "You have pity on %d of these items."
L["TEST_MSG_PITY_GIVEN_RAID"] = "You have pity on %d of these items, and %d test raiders have some too."
L["TEST_MSG_NEED_ROLL"] = "Start a roll first: click an item on the {%s} tab." -- the Loot tab
L["TEST_MSG_NEED_RAIDERS"] = "{Fill the raid} first."
L["TEST_MSG_ROLLING_ONE"] = "1 test raider is rolling."
L["TEST_MSG_ROLLING"] = "%d test raiders are rolling."
L["TEST_MSG_REROLLING_ONE"] = "1 test raider is rolling again."
L["TEST_MSG_REROLLING"] = "%d test raiders are rolling again."
L["TEST_MSG_NOBODY_ROLLS"] = "None of the test raiders can roll now."
L["TEST_MSG_FIRST_ROUND"] = "Ties are made in the first round."
L["TEST_MSG_TIE_NEED_ROLL"] = "Someone has to roll first."
L["TEST_MSG_TIE_NEED_ROLLS"] = "%d copies dropped, so %d people have to roll first."
L["TEST_MSG_TIED"] = "%s rolled %d for a total of %d, the same as %s." -- the raider, their roll, the total, the leader
L["TEST_MSG_NO_TIE"] = "None of the test raiders who are left could tie it."
L["TEST_MSG_TRADED"] = "Traded %s to %s." -- the items, the test raider
L["TEST_MSG_AS_RAIDER_ON"] = "The window now shows what a raider without officer powers sees."
L["TEST_MSG_AS_RAIDER_OFF"] = "The window shows your officer controls again."
L["TEST_MSG_REOPEN"] = "You can open the tutorial again any time with {/pl test}."

-- Slash commands (/pl help). The command words themselves stay in English. --------------------------------------

L["HELP_TOGGLE"] = "{/pl} - show or hide the addon"
L["HELP_OPTIONS"] = "{/pl options} - open the {Options} tab"
L["HELP_WRITER"] = "{/pl writer} - run loot rolls for this raid (officers)"
L["HELP_ROLL"] = "{/pl roll <item> [copies] [greed]} - start a roll"
L["HELP_ROUND"] = "{/pl close | cancel | award} - end the current round, drop the roll, or record and hand out the item"
L["HELP_DISENCHANT"] = "{/pl disenchant} - mark a BoP item no one rolled on to be disenchanted"
L["HELP_SELL"] = "{/pl sell} - mark a BoE no one greed-rolled on to be kept and sold"
L["HELP_PASS"] = "{/pl pass} - pass on the roll in progress"
L["HELP_OS"] = "{/pl os <name>} - flip a roll's off-spec flag before the first round closes"
L["HELP_PITY"] = "{/pl pity [name]} - list pity"
L["HELP_LEAVE"] = "{/pl leave <name> | rejoin <name>} - record a player leaving or rejoining the guild by hand (officers)"
L["HELP_ADJUST"] = "{/pl adjust <name> <item> <+/-pity|won> [unlock]} - correct pity, record a win, or lift a lockout (officers)"
L["HELP_RESYNC"] = "{/pl resync <officer>} - replace your ledger with an officer's"
L["HELP_STATUS"] = "{/pl status} - ledger revision, writer and warnings"
L["HELP_LOG"] = "{/pl log [count]} - the latest events in your full log, and your ledger checked against it"
L["HELP_TEST"] = "{/pl test} - walk through a raid on your own, step by step"
L["USAGE_ROLL"] = "{/pl roll <item link or ID> [copies] [greed]}"
L["USAGE_ADJUST"] = "{/pl adjust <name> <item> <+/-pity|won> [unlock]}"

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
L["MSG_ADJUST_WON"] = "%s has won %s; add {unlock} to give them pity on it again."
L["MSG_STATUS"] = "%s ledger: revision %d (%s)."
L["MSG_STATUS_SYNCING"] = "%s ledger: revision %d (%s), syncing."
L["MSG_STATUS_NO_LEDGER"] = "No guild ledger loaded."

-- Running rolls.
L["MSG_NEED_GROUP"] = "You need to be in a group."
L["MSG_WRITER_OFFICERS"] = "Only officers can be the writer."
L["MSG_LEDGER_NOT_LOADED"] = "Your guild's ledger hasn't loaded yet."
L["MSG_WRITER_ONLY"] = "Only the writer can start a roll. An officer becomes the writer with {/pl writer}."
L["MSG_WAIT_SYNC"] = "Wait until your ledger has finished syncing."
L["MSG_FINISH_ROLL"] = "Award or cancel the current roll first."
L["MSG_GREED_ONLY"] = "Nobody in the group gets much from %s, so it's a greed roll." -- the item
L["MSG_NOTHING_TO_AWARD"] = "There's no decided roll to award."
L["MSG_ONLY_SELL"] = "Only a BoE no one greed-rolled on can be kept to sell."
L["MSG_ONLY_DISENCHANT"] = "Only an item no one rolled on can be disenchanted."
L["MSG_ROLES_FAILED"] = "The roles couldn't be recorded: %s."
L["MSG_WRITER_TAKEN"] = "%s has taken over as the writer."
L["MSG_WRITER_LEFT"] = "%s, the writer, has left the raid. Another officer can take over with {/pl writer}."
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
L["LOG_CHECK_RESYNC_HINT"] = "If your log is right, {/pl adjust} puts it back: +/- pity, or {won} for a win."
L["LOG_CHECK_HINT"] = "A difference can be a change your log never saw, from a raid you weren't in or one that hasn't reached you yet."

-- Warnings: in red in chat, and in the warning sign's tooltip. -----------------------------------------------------

L["WARN_DIVERGED"] = "Your ledger differs from %s's at revision %d. If theirs is right, {/pl resync %s} replaces yours."
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
L["WHY_NOTFORCLASS"] = "this item isn't for your class"
L["WHY_OVER"] = "the roll is over"
L["WHY_BADROLL"] = "not a roll from 1 to 100"
L["WHY_ALREADY"] = "already rolled"
L["WHY_NOTREROLL"] = "not in the reroll"
L["WHY_NOPITY"] = "no pity given"

ns.L = LibStub("AceLocale-3.0"):GetLocale("PitifulLoot")

-- Raid chat and whispers -------------------------------------------------------------------------------------------

-- What the writer posts to the group, and whispers to players without the addon. Everyone in the raid reads these,
-- so they're in the language the writer picks for raid chat (Chat Language, an officer option), whatever language
-- their game is in: English, or any translation (each its own file, adding itself to ns.CHAT_LANGUAGES as below
-- whatever the game's language). A line a translation leaves out is in English.
local CHAT = {
	-- The word a player without the addon types in raid chat, or whispers to the writer, to pass ("pass" in English
	-- always works too).
	PASS = "pass",
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
	-- The whisper to a player without the addon, once a night, saying the raid uses it and how to take part.
	INTRO = "This raid is using Pitiful Loot. Type /roll or pass when an item roll starts.",
	-- The whisper to a player without the addon whose roll didn't count, and why.
	REFUSED = "Your roll for %s didn't count: %s.",
	REFUSED_RANGE_HINT = "Type /roll 100 instead.",
	WHY_LATE = "too late",
	WHY_RANGE = "rolled %d-%d",
	WHY_RAID = "not in the raid",
	WHY_WON = "already won this item",
	WHY_CANTUSE = "can't use this item",
	WHY_NOTFORCLASS = "this item isn't for your class",
	WHY_OVER = "the roll is over",
	WHY_BADROLL = "not a roll from 1 to 100",
	WHY_ALREADY = "already rolled",
	WHY_NOTREROLL = "not in the reroll",
	WHY_NOPITY = "no pity given",
}

-- Each raid chat language: its name, in itself, for the option, and its lines. Core.lua makes ns.CHAT of them.
ns.CHAT_LANGUAGES = ns.CHAT_LANGUAGES or {}
ns.CHAT_LANGUAGES.enUS = { name = "English", text = CHAT }
