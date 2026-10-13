# Pitiful Loot — Design Document

*Draft v0.10.5 · Source of truth until v1.0 · Last updated 13 Oct 2026*

**Legend:** **\[Decided\]** = stated by the project owner. **\[Proposed\]** = suggested during design review, not yet confirmed. **\[Open\]** = needs a decision.

**Versions:** each revision raises the version. A change to the rules, the roll flow or a major feature is a new minor version (0.x); smaller changes, tuning and wording are a patch (0.x.y). Every section describes the design as it stands; the revision history at the end says what changed and when.

## 1. Overview

Pitiful Loot is a WoW guild raid loot addon that adds a **per-item pity timer** to loot rolls. Every lost roll on an item makes the player's next roll on that same item stronger, so long-waiting players are favoured without ever being guaranteed a win.

### 1.1 Design tenets

1. **New players always have a real chance.** Unlikely but not impossible. About 12% against a single pity-capped player was judged right; new players are expected to be mostly locked out of heavily contested items. **\[Decided\]**
2. **Trust in the addon is paramount.** Outcomes must be verifiable. Tampering may affect what a player *sees*, never the *result*. Officers must be able to keep other Officers accountable. **\[Decided\]**
3. **Roll on every upgrade.** A player should be able to roll on every item that is an upgrade for them and accrue pity on each, with no arbitrary cap on the number of pieces. **\[Decided\]**
4. **Pity is strictly per item.** No banking pity against other items. **\[Decided\]**
5. **Need-blind.** Nobody is judged on how much they need an item, only on eligibility and how long they have waited. **\[Decided\]**
6. **Addon requirement.** Players with the addon will have more information about what's happening, but it should never be required to download it, just type /roll should be enough. **\[Decided\]**
7. **Entirely in-game.** Everything must remain in-game with the addon, no 3rd party websites are needed for tracking pity, or registering interest, or reserving items, etc... **\[Decided\]**

### 1.2 Environment assumptions

- All raid drops are BoP; BoE items are the exception (see 4.8). **\[Decided\]**
- Single difficulty, one item ID per item, so pity is never fragmented across item versions (the "Forever" setting). **\[Decided\]**
- Gear in future tiers is expected to be more horizontal (see 4.10). **\[Decided\]**
- Client: **WoW: Forever only**, at least for now (section 12). **\[Decided\]**
- Loot method: **master loot**, with officers distributing won items. **\[Decided\]**
- The addon only ever runs **outside of combat**. **\[Decided\]**
- WoW: Forever is realmless and characters carry surnames, so characters are keyed by **GUID**, not by name. **\[Decided\]**
- Every Forever class has a **single spec**, so main-spec and off-spec go by raid role (4.6), and items aren't tied to specs. **\[Decided\]**

## 2. Rules at a glance

| Rule | Value | Status |
| --- | --- | --- |
| Pity gain | +10 per lost roll, on that item only | Decided |
| Pity maximum | +50 | Decided |
| Effective roll | `min(d100 + pity + modifier, 100)` | Decided |
| Off-spec modifier | -20, no floor | Decided |
| Tie | Reroll among tied players only, pity retained | Decided |
| New player | Starts at 0 on every item | Decided |
| Winning | Does **not** reset pity; after a need win you may never roll on that item again | Decided |
| Lost rolls counted | All of them, including off-spec and any roll type | Decided |
| Pity award timing | Once, after the item is awarded, +10 to everyone who rolled except the winner | Decided |
| Not rolling, or passing | No effect on pity | Decided |
| Leaver decay | -10 pity per week until 0 | Decided |
| Absence decay | None | Decided |
| State authority | Centralised; only officers' copies are authoritative | Decided |
| Source of truth | The ledger (audit log of results); the pity table is derived from it | Decided |
| Pre-roll odds | Approximate, shown per person in the UI before the roll | Decided |

## 3. Terminology

- **Pity**: a per-character, per-item bonus from 0 to +50 earned by losing rolls on that item.
- **Capped / maxed**: a player at +50 on the item in question.
- **Fresh player**: a player at +0 on the item in question.
- **Modifier**: a roll-time adjustment (currently only the off-spec penalty).
- **Effective roll**: the final number compared between players.
- **Main-spec / off-spec**: whether the item is for the role the player is actually performing in this raid (4.6).
- **Role**: tank, healer or damage (4.6).
- **Officer**: a member of a guild rank with officer privileges (6.3).
- **Writer**: the single officer running loot rolls for the group, whose results are recorded (6.2).
- **Ledger**: the audit log of results and corrections, kept by every client; its revision is the number of entries (6.1, 6.3).
- **Round**: the opening roll for an item, or one reroll between tied players.

## 4. Rules in detail

### 4.1 Pity accrual

- A player gains **+10 pity on an item for every lost roll on it**, up to a **maximum of +50**. **\[Decided\]**
- **Every lost roll counts**: need, off-spec, and any other roll type. **\[Decided\]**
- Pity is awarded **once, after the item has been awarded**: every player who rolled, other than the winner, gains +10. Players eliminated in a tie reroll gain +10 once, not once per round. **\[Decided\]**
- **Not rolling has no effect on pity**, and nor does passing (5.2). A player without the addon can't pass, so not rolling can't be told apart from being AFK or missing the roll, and nobody should be punished for those. **\[Decided\]**
- Pity accrues at the **full rate on off-spec rolls**; off-spec rollers do not accrue more slowly. A tank who has to play DPS for a raid should not take both a roll penalty and slower pity. **\[Decided\]**
- Pity is tracked per **item ID**. **\[Decided\]**
- Pity is tracked **per character**, keyed by character GUID. Alts are disincentivised because pity accrues slower when your attendance is split; the game can't link a player's characters anyway. **\[Decided\]**
- Pity on one item can never affect another item. **\[Decided\]**

### 4.2 Effective roll

`effective = min(d100 + pity + modifier, 100)`

- `pity` is 0 to +50. `modifier` is 0 for main-spec and **-20 for off-spec**. **\[Decided\]**
- The modifier is applied **before** the clamp at 100, so it reads as "two lost rolls behind". **\[Decided\]**
- **No floor** on effective pity or on the effective roll: effective pity runs from -20 to +30 for off-spec. **\[Decided\]** Flooring effective pity at 0 would make a fresh off-spec player exactly as strong as a fresh main-spec player and remove the penalty for anyone below +20 stored pity.
- The clamp wastes overflow: each pity step is worth less than the one before it (see 7.1).

### 4.3 Ties

- Players tied on the highest effective roll **reroll among themselves only**, retaining their pity, until one player is strictly highest. **\[Decided\]**
- Because many rolls clamp to 100 at high pity, ties between capped players are common. Expect several reroll rounds in saturated pools; this is acceptable.
- **Same effective pity, no reroll**: when everyone tied has the same effective pity (including a whole roll where everyone has the same pity), their original raw rolls decide it, which gives identical odds to a reroll and saves `/roll` rounds. Tied players with different effective pity must reroll. **\[Decided\]**
- A reroll **ends as soon as every tied player has rolled or passed**, or when its time runs out (20 seconds by default). A tied player who doesn't reroll in time is dropped from it and loses; they still gain pity, having rolled in the first round. **\[Decided\]**
- **Ties that settle themselves stay out of raid chat.** A tie is announced 1.5 seconds after its reroll starts, and only if the reroll is still going. When every tied player rerolls at once (auto-roll), raid chat hears nothing until the result. **\[Decided\]** The 1.5 seconds (to allow for the round trip to the game's server): **\[Proposed\]**

### 4.3a Multiple copies

- When **two or more copies** of the same item drop from one kill, the roll works exactly as normal but stops at the **top N** instead of the top 1; each copy goes to one of those players, and each winner is locked out of the item. **\[Decided\]**
- Ties only need a reroll when they straddle the cut (for example three players tied for second place with two copies); players tied inside it all win. A reroll is for the copies left, and raid chat names the players who've already won one. **\[Decided\]**
- Everyone who rolled and did not win gains +10 pity, as usual. **\[Decided\]**

### 4.4 Winning and the lockout

- A player **may never roll again on an item they have already won** with a need roll. A greed win doesn't lock (4.8). **\[Decided\]**
- A winner may give the item to someone else (for example a friend). They stay locked out of it permanently, so gifting costs them the item. **\[Decided\]**
- Over time the pool for an item shrinks, because each winner removes themselves from it.
- An officer can lift a lockout given by mistake, or correct pity, with a recorded adjustment (`/pl adjust`, 6.1). **\[Decided\]**
- **Duplicate-equippable items** (non-Unique-Equipped items that can fill two slots, such as dual-wield one-handers, rings, trinkets): if any such item exists, the player may roll for a second copy with **pity reset to 0** for that roll, and the first copy must be **equipped** (verified by the addon) so it cannot be traded away. Such items are unlikely to exist, so this is **deferred to after v1.0 unless one is found** (`C_Item.GetItemUniqueness` can detect candidates). **\[Decided in principle; implementation deferred\]**

### 4.5 Eligibility

- A player may roll on **every item their class can use** that they want. There's no upgrade test: the addon is need-blind (1.1), so beyond main-spec or off-spec, wanting the item is enough. **\[Decided\]**
- Players cannot roll on items their character cannot use, nor need-roll an item they've won (4.4). **\[Decided\]**
- Items that are **nobody's spec in particular** (cosmetics, and anything that isn't gear, such as mounts or recipes) are open to everyone, and nobody is off-spec for them. **\[Decided\]**
- Eligibility is derived from the item's own data, not officer judgement, so there are no "sensible gear" arguments. **\[Decided\]**
- **Who can use an item** comes from the item itself, as Forever's items aren't tied to specs: a `Classes:` line on its tooltip limits it to those classes, and otherwise its armour or weapon type has to be one the class can equip (a fixed table per class, as in the original game). Rings, necks, trinkets, cloaks and off-hand items suit anyone. **\[Decided\]** The details (the table, which items count as anyone's): to be tuned in the beta.

### 4.6 Main-spec and off-spec

- The role a player rolls as is **whatever they are actually doing in the raid**: tanking means rolling as a tank, damage means rolling as damage. Rolls for gear for another role are still allowed, with the off-spec penalty. **\[Decided\]**
- Pity is per item, so switching roles between raids does not change a player's pity; only the -20 offset applies when the item is not for the current role. **\[Decided\]**
- **Off-spec is by raid role** (tank, healer or damage), as every Forever class has a single spec. A player's role is limited to what their class can do: rogues, mages, warlocks and hunters are always damage, warriors can't heal, priests can't tank, and paladins, shamans and druids can do all three; a role the class can't fill is ignored. Classes with one role are never asked or inspected. **\[Decided\]**
- **Where a raider's role comes from**, first to last: **\[Decided\]**
  1. An officer's say on the Raid tab (5.2), for everyone and for every roll from then on, including an open one. It lasts until the raider leaves the group and is kept through a reload. An officer's own inspect that's sure of a role replaces it.
  2. Their talents, when they make the role certain (below).
  3. The role Blizzard's role menu gives them (right-click a portrait or raid frame, Set Role).
  4. Otherwise their role is unknown, and rolls use their class's **fallback role**: healer for priests, damage for the rest, and tank for warriors whose talents could be read but don't reveal their spec. Their roll row shows "Off-spec -20?" when the fallback gives the penalty and "Role unknown" when it doesn't, and the flag is corrected if their role is found while the round is open.
- **Talents.** The role comes from the capstone taken in the active spec (the level 40 talent; only one can be known, and with dual spec it's the active spec's that counts). Forever's talents are trait trees, so they're read node by node from the active talent config (an inspected player's from the inspect config). A capstone is found **only by its place**, as the last (lowest) node of its tree, with the trees in their display order, never by name, as names are in the client's own language; talents whose trees can't be told apart count as unreadable. **\[Decided\]**

  | Class | First tree | Second tree | Third tree |
  | --- | --- | --- | --- |
  | Druid | Moonkin Form: damage | Berserk: tank or damage | Wild Growth: healer |
  | Paladin | Light's Vigil: healer | Holy Shield: tank | Twist of Light: damage |
  | Priest | Power Infusion: healer | Prayer of Mending: healer | Shadowform: damage |
  | Shaman | Lava Burst: damage | Rage of the Farseer: tank or damage | Riptide: healer |
  | Warrior | Mortal Strike: damage | Bloodthirst: damage | Shield Slam: tank |

  - A capstone that could mean tank or damage leaves the role unknown (the fallback, damage, is used), and an officer picks which, being offered only those two.
  - Talents without a capstone (before level 40) leave the role unknown too, and ask an officer to set it.
  - To be tuned: some Light's Vigil paladins do damage, and some Berserk druids and Rage of the Farseer shamans tank, which their defense or stamina might show (Later features).
- **Who reads the talents.** A player's own client reads them and tells the writer, again whenever they change. For players without the addon, the writer inspects them: out of combat, one at a time, a few seconds after taking over or the group changing (so clients with the addon answer first), and again when a roll starts. It inspects raiders with a role from Blizzard's role menu too, as talents come first. Someone out of range is tried next time, and someone whose talents can't be read after three inspects is left unknown. An inspect that answers during a roll settles that player's off-spec flag. Officers can also inspect from the Raid tab (5.2). **\[Decided\]**
- **An item's roles.** An item simply is a tank, healer or damage item (or more than one): a damage item is for damage, and a tank might still want it for a damage off-spec, with the penalty. Its roles are what its stats suggest (defense, dodge, parry and block for tanks; spirit, healing, mana regeneration and intellect for healers; strength, agility, attack power, hit, crit, spell damage and intellect for damage), or an officer's say: any officer can right-click an item (on the Loot tab, or the item at the top of the Roll tab) and tick the roles it's for, which is recorded in the ledger so every client agrees and later drops use it. Items whose stats say nothing, and anything that isn't gear, suit every role. A roll is off-spec when the player's role isn't one of the item's. **\[Decided\]** The stat rules: to be tuned in the beta.
- Changing an item's roles while its roll is open updates everyone's off-spec flag at once. The writer can still flip any roll's flag by hand before the first round closes (click the row, or `/pl os <name>`). **\[Decided\]**
- To stop role-swapping to dodge the penalty, a player's role (other than an officer's say) is **kept from the first time a roll uses it**, until they leave the group. A genuine mid-raid swap is handled by an officer setting their role, or the writer flipping the flag. **\[Decided\]**

### 4.7 New players

- A new player starts at **0 pity on every item**. **\[Decided\]**
- They are expected to be mostly locked out of heavily contested items but always keep a nonzero chance (see 7.3).
- Their position improves over time as pity accrues, and veterans win and lock themselves out of each item, and at the start of a new tier, when everyone is at 0.

### 4.8 BoE items

- First a **need roll** for players who need the item for gear. **\[Decided\]**
- If nobody needs it, a **greed roll**, which the writer starts (no message announces it's coming). **\[Decided\]**
- Pity rises for greed rollers **only if the greed roll actually happens**. **\[Decided\]**
- Greed-roll pity is held in a **separate counter** and can never be used as need-roll pity. **\[Decided\]**
- **Winning a greed roll doesn't lock the winner out** and changes none of their pity, so they can still need-roll the item if it becomes an upgrade. **\[Decided\]**
- **Everyone may greed-roll**, whatever their class and even if they've won the item. **\[Decided\]**
- **There's no off-spec on a greed roll**: greed is purely for gold or materials. **\[Decided\]**
- A BoE **no one greed-rolls on is kept and sold** (it's worth more on the auction house than disenchanted): the writer's **Keep to sell** button, and the master looter takes it. Nothing is recorded. **\[Decided\]** The button's wording: **\[Proposed\]**

### 4.9 Decay and leaving

- **Leavers**: a player who leaves the guild loses **10 pity per week until 0**, on every item, so they can rejoin but at a cost. The first -10 comes 7 days after leaving, not on the day. **\[Decided\]**
- Leaving and rejoining are **recorded automatically**. Officers' clients compare the guild roster with the ledger. The online officer with the highest rank (then first by name) records the change; the others wait longer, in that order, and only step in if it still hasn't been recorded. Decay counts from when the leave was first seen, and stops on rejoining. Officers can also record either by hand (`/pl leave`, `/pl rejoin`). **\[Decided\]**
- **Absent members** (still in the guild) **don't decay**: pity only ever rewards waiting, and there's no attendance to record. **\[Decided\]**

### 4.10 New tiers and horizontal gear

- New-tier items start at 0 for everyone (a consequence of per-item pity); old-tier pity stays but is moot.
- Gear is expected to become more horizontal, so more players will want each piece and pools will be larger, which makes the new-player odds in 7.3 worse. This is accepted as covered by class-eligibility plus once-per-item, and will be **reviewed after the first tier** (raids open 9 Dec 2026) using real pool sizes from the ledger. **\[Decided\]**

## 5. Roll flow and UI

### 5.1 Flow

1. The master looter loots a boss and the item list is shared with the group (5.2, Loot tab). The writer starts a roll on an item, announced in raid chat so players without the addon see it. Rolls run **one item at a time**, because a plain `/roll` cannot say which item it is for. **\[Decided\]**
2. Eligible players (4.5) roll with `/roll` (1-100), or the window's roll button, within the roll time (30 seconds by default). Players with the addon can pass instead (5.2). A last call goes to raid chat 5 seconds before the opening round closes. **\[Decided\]**
3. The writer counts each player's **first roll in the round**; later rolls, rolls with a range other than 1-100, rolls from outside the group, and rolls from players who can't use the item or have won it are refused. A roll up to 10 seconds after the roll is decided is refused as too late; later ones are ignored. A refused player without the addon is told why by whisper, once per roll; players with the addon, the writer included, see why on their own row on the Roll tab instead (5.2). **\[Decided\]**
4. The writer sends the counted rolls to the group as they come (every half second), and every client checks each against the `/roll` it saw itself (6.1). The round closes when its time runs out, or when the writer clicks Close round.
5. The writer works out effective rolls and resolves any ties by rerolling among the tied players (4.3).
6. The winner is announced with the full breakdown (5.3). The writer awards the item, by hand or automatically (an option), and master loot gives it to the winner. If it can't be given by master loot, it's traded to the winner and listed as awaiting trade until the trade goes through (5.2); if the winner is the officer who looted it, they already have it and nothing is listed. A BoP item no one rolled on is disenchanted instead: nothing is recorded, and the master looter takes it; a BoE no one need-rolled on can go to a greed roll, and one no one greed-rolled on is kept to sell (4.8). **\[Decided\]**
7. Awarding appends the result to the ledger as a new revision, sent to the guild (6.3); replaying it gives every player who rolled, other than the winners, +10 pity on the item (to a maximum of +50).
8. The writer can cancel a roll at any point before it's awarded; nothing is recorded.

### 5.2 UI requirements

**The window.** One window with side tabs, as the group finder has: **Roll**, **My pity**, **Loot** (once loot has been seen), **Raid** (officers, and members who show it) and **Options** (always the bottom tab). It's made from the base game's own templates and art so it sits alongside its panels. The header shows the item being rolled for, its round, the time left and a timer bar, and where it dropped. The footer shows the ledger's revision and the officer who recorded it (`Rev 12 by Ofelia`; just `Rev 12, syncing` while it's syncing) over the writer, always on two lines. The writer's buttons sit bottom right: one for whatever comes next (Close round, Award, Greed roll, Keep to sell or Disenchant), plus Cancel; other officers in a group get **Be the writer**. A warning sign top right lists anything that didn't match what this client saw (6.3), until clicked. The window is dragged by its frame and resized from a handle at its foot (right-click resets the height); its place and size are kept for the account. `/pl` opens it, as does the minimap button. **\[Decided\]**

**Throughout.**
- **Every player's name is shown in their class colour.** **\[Decided\]**
- **Click hints**: tooltips end with green lines saying what clicking does, only for players who can do it; an option hides them. **\[Decided\]**
- The pity table is visible to everyone with the addon. **\[Decided\]**
- Hiding rolls from other players is **not needed**: rolling is free and a roll cannot be changed after it is seen. **\[Decided\]**
- **Announcements** are plain sentences without the addon's name, to keep them easy to skim (5.3). They go to **raid chat** (party chat in a party), never `/say`, so everyone in the group sees them with or without the addon. When the writer is raid leader or an assistant, the headlines (a roll starting, a tie, the result, no rolls) are **raid warnings**; breakdowns stay in raid chat. Options turn announcements and raid warnings off; the whispers about refused rolls (5.3) have an option of their own. **\[Decided\]**

**Odds.**
- **Pre-roll odds per person** are shown before the roll. **\[Decided\]** They only need to be **approximate**; the actual outcome is what matters. The pool is assumed to be everyone who has rolled plus everyone in the group with pity on the item, less anyone who passed. Odds use the same tie-reroll mechanism as the real roll (7.5) and include the off-spec modifier. **\[Decided\]**
- The odds **update live**: when a roll is seen from a player not already in the assumed pool, they are added. Odds use only **who is in the pool and their effective pity**, never the values already rolled. This is safe because rolling can only ever help a player, whatever the other rolls are. **\[Decided\]**
- **Every client works out the odds itself**, from the same seed (7.5), so everyone sees identical numbers without the writer sending them: less addon traffic. **\[Decided\]**
- **Your chance goes under your roll.** The large figure on the right of a row is only ever the roll's total; the chance to win sits under it. Your own row shows your chance before you roll even if you have no pity (worked out with you added to the pool, on your client only, so everyone else's figures still match every other client's). **\[Decided\]**

**The Roll tab.**
- Each row shows a player's roll, their pity and any off-spec penalty in even columns, with the total on the right. Hovering shows the breakdown; the writer clicks a row to flip its off-spec flag before the first round closes. **\[Decided\]**
- While a player can roll, **their own row sits at the top with "Click to roll"** across it, which does the `/roll 1-100` for them, with their chance of winning on the right; typing `/roll` still works the same. Their own row is always highlighted. A roll a player can take part in opens the window on the Roll tab (an option turns this off). **\[Decided\]**
- **Your roll shows as soon as you make it.** Your row stays at the top from the moment you click until the game says what you rolled, then shows that roll where the writer's count will put it, without waiting the half second for the writer's message. **\[Decided\]**
- **Passing.** Your row has the group loot roll's pass button in its top right corner, apart from the rest of the row, which rolls. Passing changes nothing in the ledger (not rolling never does), but it takes you out of everyone's odds, shows you as passed, stops auto-roll, and ends a reroll sooner. A `/roll` after passing still counts. Passes aren't announced in raid chat. **\[Decided\]**
- **Auto-roll** (an option, off by default) rolls for you: in rerolls only, straight away; or in every roll you can take part in, after 5 seconds in a new roll so you can pass first, with a countdown on your row. **\[Decided\]**
- **In a reroll**, the tied players have their own section above everyone else, during the reroll and after it, and their earlier rolls stay on their rows, greyed out, until they roll again, so the tie can still be seen but new and old numbers aren't confused. Players out of it keep their roll and their odds from before the tie. **\[Decided\]**
- **A roll you can't take part in** still shows, with your own row at the top, greyed out, saying why (your class can't use it, you've won it, or only the tied players reroll). It never opens the window by itself; it's there if you look. **\[Decided\]**
- **A roll of yours that didn't count** shows the same way, with the writer's reason: while no roll of yours counts, your row's details say `Didn't count: rolled 1-50` (or already won this item, can't use this item, not in the reroll, too late, not in the raid), and its tooltip says it in full (`Your roll of 30 didn't count: rolled 1-50.`). After a wrong range you can still roll, so the row keeps its roll button, and its tooltip adds that only a roll from 1 to 100 counts. Once a roll of yours counts, the row shows that, and a roll that didn't count (a second one, say) is only in its tooltip. **\[Decided\]**

**The Loot tab.**
- **The loot is shared with the whole group.** The officer who loots the boss (the master looter) sends the item list, and everyone's Loot tab shows each item's roll: rolling, won, awarded (greyed out, with the winners' names) or no one rolled, plus their own pity on it when they have some. Each boss's loot is a group headed by the boss, in the order it was seen; new loot opens its group and the items awaiting trade, folds the other groups away, and opens the window on the Loot tab (an option, on by default for everyone, turns this off). Opening the same corpse again never adds its loot twice, even once some of it has been handed out (the corpse's GUID identifies it, or failing that the same items). **\[Decided\]**
- Each item shows the game's borderless role icons (the group finder's, for players listed on their own) for the roles it's for, at the start of its details line and with no words, unless it's for every role. **\[Decided\]**
- An option hides the items you can't roll on (your class can't use them, or they're a later drop of an item you've won; the copy you won stays, and BoEs always show, as anyone can greed-roll them), and then loot that's all like that doesn't open the window. The writer always sees everything, as rolls are started from it. **\[Decided\]**
- Only the writer can start rolls from it: left-click an item for a roll; right-click a BoE for a greed roll. Officers right-click an item for a menu with its roles (and the greed roll, for the writer). **\[Decided\]**
- **After an award or a disenchant**, the writer is taken back to the Loot tab while there's loot left to roll for or hand over, copies awaiting trade included, and after an automatic award too. **\[Decided\]**
- **Won items awaiting trade** are listed at the top of the Loot tab, one row per copy: every one for officers, and your own for you. Each shows who it's for and who has it, and the time left to trade it (red under 30 minutes). Either side's client sees the trade go through and tells the group, so everyone's list stays current; officers can also right-click one to mark it handed over. An officer holding a copy left-clicks it to open a trade with the winner (or is told they're too far away); whenever a trade opens between them, whoever opened it, the copies the officer holds for the winner go in, a copy still inside its trade window first. A trade that goes through is checked off automatically; marking by hand is the fallback. Copies given by master loot, and copies won by the officer who looted them, are never listed. **\[Decided\]** Only officers' clients putting items in (so a member's own copy of the same item is never offered), and taking `traded` only from officers or the winner: **\[Proposed\]**
- **Trades are finished by hand**: a person clicks Trade on each side, as the game doesn't let addons accept a trade (section 12). **\[Decided\]**
- **Loot is kept through a /reload or logging out**, per character, and after leaving the group while copies are still to be handed over, so nothing awaiting trade is lost. Loot older than the trade window is dropped; out of a group, so is loot with nothing left to hand over. A late joiner gets the writer's copy. **\[Decided\]**

**The My pity tab.**
- Your pity on each item, need and greed, and the items you've won, with how much better your odds are than with no pity, one on one (from 7.1). **\[Decided\]**
- Grouped under the raid each item drops in, with an option to group by boss inside each raid. Groups collapse. Entering a raid opens its group (bosses included) and folds every other raid away; after that the groups stay as you leave them until you next enter a raid. Where an item drops is recorded with each roll (the writer's instance, and the boss last killed there); items with no recorded source go under Other. An option hides items you've won. **\[Decided\]**

**The Raid tab.** **\[Decided\]**
- **Who sees it**: officers always have it. Members can show it with an option (Show the Raid Tab, which officers don't see), just to look at: they can't click anything on it, and get no hints.
- **Layout**: a line at the top with how many tanks, healers and damage there are and how many are unknown, then the raid groups two to a row, each on a faint panel with its number in the corner, and in each a line per raider of their role's icon and their class-coloured name (grey while offline), in raid order as the game's raid frames have them. Twenty raiders fit without scrolling; forty scroll a little.
- **Unknown roles** have a question mark in place of the icon and a tinted line: light blue while their talents haven't been looked at yet or are being looked at, red when looking went wrong; the top line counts each kind as a question mark in its colour.
- **Inspect Unknown**, top right for officers, inspects every raider whose role is unknown, one at a time, whatever was tried before, and never a raider whose role is known. It reads "Inspecting..." while on, and chat says how it went.
- **Left-clicking** a raider whose class has a choice of roles inspects them straight away and reads their role from their talents, whatever was known before (an officer's say aside, 4.6). The result is printed, and an officer who isn't the writer sends it to the writer, whose view everyone sees.
- **Right-clicking** a raider whose class has a choice of roles offers those roles (only tank or damage when their capstone leaves just those) and Automatic, which goes back to working it out and shows the role that would give as its icon (a question mark while unknown). The choice is sent to the whole group and only taken from officers.
- **The tooltip**: under the raider's name, while an officer's inspect is under way, "Inspecting their talents" in light blue with dots that count up; otherwise, if looking at their talents last went wrong, why, in red ("Too far away. Try again when closer.", "Inspect got no response. Try again.", "Talents couldn't be read. Try again.", "Talents are ambiguous. Please set tank or damage." or "Talents don't reveal their spec. Please set it."; the last two go once an officer has set the role). Then their role with its icon, in white, and where it came from only if that isn't certain: "Set by" an officer or "Set in Blizzard's role menu"; a role from talents, or a class with one role, says nothing. An unknown role shows the question mark, in its colour, with the fallback role. Then their group, and for officers the hints "Left-click to update role from talents" and "Right-click to set their role." The tooltip is redrawn as things change while it's hovered.
- Other officers see the writer's view of the roles, which the writer sends whenever it changes.

**Options.**
- All options are on the Options tab (there's no page in the game's settings), and kept in profiles (AceDB's): every character starts on Default, so they share their options, and the Profile section at the bottom of the tab (This Character, a dropdown) picks another profile for this character, makes a new one (named in a dialog, with the default options), copies another's options in, resets this one, or deletes another; copying, resetting and deleting ask first. The window's place and size, the minimap button's place and which My pity groups are folded are kept for the account, outside the profiles. **\[Decided\]**
- General options: auto-roll, open the window when you can roll, open it on the Loot tab when loot is added, hide loot you can't roll on, group My pity by boss, hide won items, the minimap button, show the Raid tab (members only), and the click hints. **\[Decided\]**
- Officer options, hidden unless an officer ticks **Officer options** in the tab's corner (members never see them): announcements in raid chat, raid warnings, whispering refused rolls, roll and reroll times, loot quality, and awarding automatically. **\[Decided\]**
- **The minimap button** is made with LibDBIcon, like most addons' buttons: left-click for the window, right-click for options, drag to move. The addon is also listed in the minimap's addons menu, which Forever keeps hidden. **\[Decided\]**

### 5.3 Raid chat messages

All go to raid chat (party chat in a party); "headline" ones are raid warnings when the writer may send them. They stay in **English** whatever language the writer's game is in, as the whole raid reads them; they're kept apart from the rest of the text (5.4) so a Chat Language option can offer translations later. **\[Decided\]**

| When | Message | Headline |
| --- | --- | --- |
| An officer becomes the writer | `Ofelia is running loot rolls.` | |
| Another officer takes over a roll | `Bram has taken over the roll for [Item].` | |
| A roll starts | `[Item]: /roll now (30s)`, with `(2 copies)` after the item, or `Greed roll for [Item]: /roll now (30s)` | Yes |
| 5 seconds before the opening round closes | `5 seconds left to /roll for [Item].` | |
| A tie | `Tie for [Item] between Lary, Tobin: /roll again (20s).` | Yes |
| A tie after some copies are won | `Tobin wins [Ring].` (or `Tobin, Mira win`) then `Tie for the last copy of [Ring] between Mira, Lary: /roll again (20s).` (or `the last 2 copies of`) | The tie |
| The result | `[Item] goes to Mira.` | Yes |
| Each winner's breakdown | `Mira: 90`, `Lary: 62 + 50 pity - 20 off-spec = 92`, `Lary: 62 + 50 pity = 100 (max)`, with `(reroll)` for a reroll | |
| No one rolled | `No one rolled for [Item].` | Yes |
| A roll is cancelled | `The roll for [Item] was cancelled.` | |
| A BoP item no one rolled on | `[Item] will be disenchanted.` | |
| A BoE no one greed-rolled on | `[Item] will be sold.` | |
| A refused roll, from a player without the addon (a whisper, once per roll) | `Your roll for [Item] didn't count: already won this item.`, and for a wrong range `...didn't count: rolled 1-50. Type /roll 100 instead.` | |

- A breakdown never says `pity +0`, and says `(max)` when the clamp at 100 cut a total. **\[Decided\]**
- A tie is held back for 1.5 seconds and dropped if everyone has rerolled by then (4.3), so instant rerolls don't fill raid chat. **\[Decided\]**
- **Refusal whispers** go only to players without the addon (players with it see why in the window, 5.2), and never from the writer to themselves: the writer knows who has the addon because every client answers a new writer, and anything a client sends counts. An officer option (Whisper Refused Rolls, on by default) turns them off, apart from the raid chat messages. **\[Decided\]** The reasons: too late, rolled (another range), not in the raid, already won this item, can't use this item, already rolled, not in the reroll. **\[Decided\]**
- The last call is in raid chat, not a raid warning. Ending the opening round once every eligible player has rolled or passed (Later features) would make it rarer. **\[Decided\]**
- No message says a greed roll is next after no one needs a BoE. **\[Decided\]**

### 5.4 Text and languages

- **All the text players see is in one file**, `Locales/enUS.lua`, by AceLocale-3.0 (the usual way for addons built on Ace3, as Bartender4, Details and RCLootCouncil do it). Code uses each line's code name (`L.TAB_ROLL`), and the file groups the lines by where they show, with notes on their placeholders. A name with no line shows as itself, with an error. **\[Decided\]**
- The text is **British English**, registered as enUS, as the game has no other English locale. **\[Decided\]**
- **A translation** is a file per language, loaded after the English one, that sets the lines it translates; anything it leaves out stays in English. If the addon goes on CurseForge, those files can hold its packager's `@localization` placeholder, so translators work on the website. **\[Decided\]**
- **Raid chat and whispers** are a separate English-only table (5.3). **\[Decided\]**
- **Nothing that travels between clients is text** a player reads: refusal reasons and why a player can't roll are codes, which each client puts into its own words. **\[Decided\]**
- **Nothing depends on the client's language**: game text the addon reads (`/roll` results, an item's `Classes:` line, trade messages) is matched with the game's own localised strings, and talents by their place (4.6). **\[Decided\]**
- Slash command words (`/pl writer`) and the temporary test tooling aren't translated. **\[Decided\]**
- Every line is to have a review by hand, in that file, by the project owner (10).

## 6. Authority, trust and data sync

### 6.1 Central state

- Pity state is **centralised**. Only officers' copies are authoritative; discrepancies between officers are investigated. **\[Decided\]**
- Everyone else's copy is a read-only cache for their own reference and for catching discrepancies. **\[Decided\]**
- The **ledger is the source of truth**; the pity table is derived from it by replaying it. **\[Decided\]**
- Outcomes are derived from the **recorded `/roll` chat results**, never from addon-side random numbers. `/roll` results are server-generated system messages that players cannot forge, and the raid sees them, so every client with the addon can independently verify each logged result. **\[Decided\]**
- The ledger records each award (all rolls, entrants, pity and modifiers, winners, and where the item dropped), and every change outside a roll: guild leaves and rejoins (4.9), officers' adjustments to pity or lockouts (4.4), and officers' say on an item's roles (4.6). Replaying it always reproduces the same table. **\[Decided\]**
- Every client checks the writer as it goes: each counted roll against the `/roll` it saw, any `/roll` it saw that wasn't counted, the pity the writer used against its own ledger, the winners against the rolls, and the recorded award against the roll it watched. Anything that doesn't match is a warning, in chat and on the window's warning sign. **\[Decided\]**

### 6.2 Single writer

- One officer is the **writer** for each group, running every roll; other officers hold mirrors of the roll in progress. This avoids two officers writing conflicting results. An officer becomes the writer with **Be the writer** or `/pl writer`, and the group is told. **\[Decided\]**
- If the writer leaves, disconnects or reloads mid-roll, **another officer takes over** as writer, carrying on from their own copy of the roll. When the writer leaves the group, everyone is told another officer can take over. **\[Decided\]**
- Players who join part way through ask who the writer is and get the roll in progress, the loot and the roles; they can't check rounds they didn't see. **\[Decided\]**
- The writer also inspects raiders for their roles and shares its view of them (4.6, 5.2). **\[Decided\]**

### 6.3 Publishing the pity table

- The ledger is **published to everyone with the addon**, in the guild channel. **\[Decided\]**
- **Only officers can push updates**, and clients accept updates **only from officers**. Every entry is replayed and checked before it's kept. **\[Decided\]**
- The game stamps the real sender name on addon messages, so "is the sender an officer" can be checked against guild rank. **\[Decided\]**
- **Officers are the guild ranks given officer privileges in the guild's own rank settings** ("Has officer privileges", what the game itself means by an officer), so every client agrees without any setting. The guild master always counts. If a client can't read the rank settings, ranks 0 and 1 count. **\[Decided\]**
- **Syncing**: everyone says hello to the guild on logging in, with their revision and hash; an officer ahead answers, and the client fetches the entries it's missing from that officer, in batches. A new entry an officer records goes to the guild at once. While its copy is syncing, the writer can't record anything. **\[Decided\]**
- A tampered client only changes what that player sees; it cannot change an outcome. **\[Decided: accepted risk\]** The real risk is a tampered *officer* client, but every other player in the raid with the addon checks the writer (6.1).
- The ledger is a **hash chain**: each entry carries the hash of the one before it, so the head hash covers the whole history and therefore the table, and the revision is the number of entries. The footer shows the revision and the officer who recorded its last entry. **\[Decided\]** A way to verify that a revision is legitimate, beyond what clients that watched a roll can check, is a later feature (10).
- A copy that doesn't follow on from an officer's is **never overwritten silently**: the player is warned, and `/pl resync <officer>` replaces it with that officer's. **\[Decided\]**
- The hash detects **divergence, not authenticity**: a tampering officer can produce a valid hash for a fake table. Authenticity comes from every client checking each new entry against the rolls it observed. **\[Decided\]**

## 7. Odds reference

All figures are exact (tie rerolls included) and were cross-checked by simulation.

### 7.1 Win chance versus a fresh player (+0)

| Pity | Win chance |
| --- | --- |
| +0 | 50% |
| +10 | \~60% |
| +20 | \~68% |
| +30 | \~76% |
| +40 | \~82% |
| +50 | \~88% (a capped player still loses about 1 in 8) |

### 7.2 Off-spec head-to-head

| Matchup | Off-spec wins | Main-spec wins |
| --- | --- | --- |
| Fresh off-spec (-20) vs fresh main-spec | \~32% | \~68% |
| Fresh off-spec (-10) vs fresh main-spec | \~40% | \~60% |
| Fresh off-spec (-20) vs capped (+50) main-spec | \~4.4% | \~95.6% |
| Fresh off-spec (-10) vs capped main-spec | \~7.8% | \~92.2% |
| Capped off-spec (+30 effective) vs capped main-spec (+50) | \~32% | \~68% (raw: 27% / 57% / 16% tie) |
| Capped off-spec (+30 effective) vs fresh main-spec | \~76% | \~24% |

Stored pity of 20 or more makes an unfloored -20 and a floored-at-0 off-spec roller identical; below +20 the floor removes the penalty.

### 7.3 New player (+0) against k capped (+50) players

Pity is per item, so a new player does not build pity across items within a raid; each item is an independent roll at +0.

| Capped opponents | Win chance per item | At least 1 of 6 items | None of 6 |
| --- | --- | --- | --- |
| 1 | 12.4% | 54.7% | 45.3% |
| 2 | 4.1% | 22.4% | 77.6% |
| 3 | 1.6% | 9.1% | 90.9% |
| 4 | 0.65% | 3.8% | 96.2% |
| 5 | 0.29% | 1.7% | 98.3% |
| 6 | 0.13% | 0.8% | 99.2% |
| 8 | 0.03% | 0.2% | 99.8% |

The 12% in the design tenets holds only against **one** capped player. This is the worst case; it eases as winners remove themselves from the pool and resets at tier launch. The cap stays at +50 rather than +40 (7.4). **\[Decided\]**

### 7.4 If the cap were lower (not adopted)

| Cap | Capped vs fresh | New player vs 1 / 3 / 8 capped |
| --- | --- | --- |
| +50 (current) | \~88% | 12.4% / 1.6% / 0.03% |
| +40 | \~82% | 17.9% / 3.3% / 0.15% |
| +30 | \~76% | 24.4% / 6.0% / 0.5% |

### 7.5 How the window works out odds

- **Method**: simulation, 10,000 trials through the real ranking code, spread over frames (1,000 a frame) so a 40-player pool doesn't stall the game, seeded from the pool's makeup so every client shows identical figures. Players with the same bonus share one figure. Pools where everyone has the same bonus, or with as many copies as players, are exact (`copies / players`). **\[Decided\]**
- **The exact calculation**, used to check it: for each player, effective pity `e = pity + modifier`, and each roll is `min(d + e, 100)` for `d = 1..100`. `P(i wins)` for a pool is the sum over each value `v` that `i` can roll of `P(i rolls v)` times: `P(every other player rolls below v)`, plus, for each non-empty subset `S` of the others who tie at `v` (the rest rolling below), the probability of that outcome times `W(i, S)`, where `W` is the same calculation applied to the sub-pool `{i} ∪ S` (a reroll, pity retained). Players with the same effective pity are interchangeable, and effective pity takes only a handful of values, so it can be memoised on the count of players at each value.
- **Validation**: the exact recursion matched simulation (a new player against 3 capped players: 1.58% exact, 1.59% simulated).

## 8. Exploit review

| Concern | Disposition |
| --- | --- |
| Rolling on everything to farm pity | Not possible: pity is per item and players can only roll on items their class can use (4.5). |
| Alts and extra characters | Pity is per character, so playing one character means not playing another; alts accrue pity slower. **\[Decided\]** |
| Win then give the item to a friend | Allowed. The winner is locked out of that item permanently. |
| BoE and vendor items | Raid drops are BoP. BoE: need roll first, then greed roll with a separate pity counter. |
| Seeing rolls before committing | Irrelevant: rolling is free and rolls cannot be changed. |
| Tampering with pity state | Centralised officer-held state; clients accept only officer updates; hash chain, and every client checks the writer (6). |
| Role-swapping to dodge the off-spec penalty | A role is kept from the first time a roll uses it; officers can set a role, and the writer can flip a roll's flag (4.6). **\[Decided\]** |
| Spamming rolls or odd roll ranges | First roll per round only; rolls outside 1-100 refused (5.1). **\[Decided\]** |
| Returning with stale high pity | Accepted: pity rewards waiting, and only leaving the guild decays it (4.9). **\[Decided\]** |
| Passing an item to dodge the lockout (duplicates) | Pity reset plus first copy must be equipped (4.4). **\[Deferred\]** |

## 9. Accepted shortcomings (explicitly decided)

- **Pity saturates after 5 losses.** If 8 people have all waited around two months for an item, everyone ends up at +50 and someone has to win; it becomes a lottery among long-waiters. **\[Decided\]**
- **New players are mostly locked out** of contested items (7.3), but never completely. **\[Decided\]**
- **Need-blind**: no weighting by how big the upgrade is. **\[Decided\]**
- **No cross-item fairness**: a player can win several items in a run. To reach five items at +50 they must have lost every one of them repeatedly. **\[Decided\]**
- **Pity is not a guarantee**: a +50 player still loses about 12% of the time to a fresh player, and half the time to another +50 player.
- **Off-spec pity accrues at the full rate**, so a long-waiting off-spec player (+50 less 20 = +30) beats a fresh main-spec player about 76% of the time. **\[Decided\]**
- **Diminishing returns** from the clamp at 100: the first +10 adds about 10 points of win chance, the last about 6.
- **Roles can be wrong** until an officer sets them, where talents are ambiguous or unreadable; rolls then use the class's fallback role (4.6). **\[Decided\]**

## 10. Open questions

1. **Tuning from the beta**: who can use an item (4.5), the roles items suit (4.6), and roles from talents (4.6).
2. **Runtime behaviour still to confirm in the beta client**: `Beta Checks.md` has the checks and results so far, and section 12 what's been confirmed. Still open: addon messages with other players, how long a full ledger sync takes, master loot handing items to the winner, inspecting at a 1.5 second gap, and capstones once talents reach level 40.
3. **Addon message limits.** Messages go through AceComm and ChatThrottleLib, which pace them by bandwidth and retry any the client reports as throttled; live roll messages go out before ledger sync. The harness assumes the client allows 10 messages at once per prefix, then 1 a second. If that's right, live rolls fit (they're batched), but a first full ledger sync is slow (roughly 250 bytes a second per officer, after compression). Measure in the beta.
4. **Review of every line players see**, in `Locales/enUS.lua` (5.4), by the project owner.
5. Duplicate-equippable items (4.4): build only if one actually comes up.

### Later features (agreed, not yet built)

- **A test menu.** A separate popup window that gathers every test command (`/pl test ...`) behind buttons and fields, instead of typing them. Part of the temporary test tooling, so it goes with it before release unless kept for development.
- **Roles from talents and gear.** When some roles are worked out from talents together with gear or stats (defense, stamina: a Berserk druid or Rage of the Farseer shaman who tanks, a Light's Vigil paladin who does damage), their tooltip's source line reads "Found from talents/gear".
- **A Chat Language option**, once there are translations of the raid chat messages (5.3, 5.4).
- **Verifying revisions.** An actual system to check that each revision of the ledger is legitimate, so the footer can say a revision is verified rather than only who recorded it. Today the hash chain only shows copies have diverged, and only clients that watched a roll check its entry (6.3); a client that wasn't there, or an entry recorded outside a roll (an adjustment, a leave, an item's roles), has nothing to check it against. To be designed.
- **End the opening round early** once every eligible player in the raid has rolled, as rerolls already do. Needs a reliable idea of who is eligible (class, lockouts, and whether someone simply doesn't want the item), so it isn't built yet. Passing (5.2) now covers "doesn't want it" for players with the addon.
- **Several items in a row (draft, not agreed).** Rolls stay one item at a time, as a plain `/roll` can't say which item it's for; this is about running them back to back. **\[Proposed\]**
  - *Roll all*: a button on each boss's loot header, for the writer, that queues every item in it still to roll for, in loot order, need rolls before greed rolls.
  - *Queue*: shift-clicking an item on the Loot tab adds it to the queue instead of starting it; the queue shows as numbered badges on the items, and right-clicking a queued item takes it off.
  - *Running the queue*: the next roll starts a few seconds after the last is awarded or disenchanted, and raid chat says where it's got to (`[Item] (2 of 5): /roll now (30s)`). Ties pause the queue until they're settled. Award Automatically makes it run unattended; without it, it waits for each Award. A BoP item no one rolls on is left for the writer to disenchant (or disenchanted automatically, as an option) and the queue moves on.
  - *Safety*: Cancel stops the current roll and asks whether to stop the queue too; the queue goes in the writer's state reply, so an officer taking over carries on with it.
  - *Not proposed*: rolling several items at once with different roll ranges (`/roll 101-200` for the second item), which breaks "just /roll" (1.1) and the 1-100 rule.
- **Gargul popups for raiders without Pitiful Loot (draft, not agreed).** Raiders who run Gargul but not Pitiful Loot should get Gargul's own roll popup when a roll starts, and its "you won" notice on an award, as if Gargul were running the loot. **\[Proposed\]**
  - *What Gargul does* (read from Gargul 8.0.1's source, 10 Oct 2026; not tried in game). It has a Forever build. Its messages use the prefix `GargulComm2`, packed with LibSerialize and LibDeflate. Starting a roll shows every Gargul user a popup with one button per roll range the sender lists (each does a `/roll` in that range) and a Pass button; it doesn't check who sent it. Stopping one is only accepted from whoever started it, and an award gives the winner the game's "You won" toast and adds it to everyone's Gargul history. Gargul doesn't react to raid chat or raid warnings, so today Gargul users only see Pitiful Loot's announcements in chat.
  - *How*: the writer's client sends Gargul's own "start roll" message when a roll or reroll starts, with a single **Roll (1-100)** button (Gargul's default off-spec 1-99 roll would be refused, 5.1), the time left, and a note (`Pity roll` or `Reroll: Lary, Tobin only`); its "stop" when the round closes; and its "award" when the roll is awarded. An officer option turns it off.
  - *Risks*: this copies Gargul's internal message format, which has no promise of staying the same (its message numbers changed recently), so a Gargul update can quietly break it; it needs two more libraries; players running both addons get two popups unless Pitiful Loot asks Gargul to skip them, which it can't. A safer but narrower alternative: when the writer also has Gargul, call the functions Gargul offers other addons (`Gargul.RollOff:announceStart`), though that only works for writers with Gargul installed and makes Gargul post its own chat lines too.
  - *Recommendation*: copy the message format, check it against each Gargul release, and switch it off by itself if Gargul's minimum version moves past the one it was built for.
- **Letting the raid know Pitiful Loot exists (draft, not agreed).** Players without the addon only see plain raid chat (5.3), which never names the addon. A quiet way to tell them, without nagging anyone. **\[Proposed\]** Options:
  1. *Whisper once*: the first time someone `/roll`s in a roll without the addon, the writer's client whispers them one line, at most once per player: `These rolls use Pitiful Loot: each roll you lose on an item adds pity to your next roll on it. /roll is all you need; the addon shows your pity and odds.` The writer already knows who has the addon (5.3).
  2. *Name it once per raid* in the line that already says who's running loot: `Ofelia is running loot rolls with Pitiful Loot.` One line a night, seen by everyone, including people who already know.
  3. *Leave it to the breakdowns*: results already say `62 + 50 pity = 100`, which invites the question. Costs nothing, but tells no one where to look.
  - *Recommendation*: 1, as it only reaches people who don't have the addon, once each, privately; with 2 as the fallback if whispers feel too pushy.

## 11. Alternatives considered, not adopted

- **Strict tiers** (any main-spec roller beats any off-spec roller): breaks the new-player tenet for off-spec rolls.
- **Hard pity** (guaranteed win after N losses): the soft system was preferred.
- **Uncapped `d100 + pity`** (no clamp at 100): would remove mass ties and the diminishing returns, but was not chosen.
- **A lower cap** (+40 or +30, 7.4): better odds for new players, but the cap stays at +50.
- **Cross-item penalties** for recent winners: rejected; sweeping several items is acceptable.
- **Hiding rolls until all are in**: unnecessary since rolling is free.
- **Calling players roll-locked** from the fourth reroll in a row, in raid chat and the window's header: dropped, as rerolls are quick (they end once every tied player has rolled) and often automatic, so a long run of ties is nothing to remark on.
- **An upgrade test** for eligibility: rejected, as the addon is need-blind (4.5).
- **Specs for off-spec** (inspected specs, items' spec lists): Forever has one spec per class and items aren't tied to specs, so off-spec goes by raid role (4.6).
- **Finding capstones by name**, when the talent trees can't be told apart, or from the spellbook: dropped, as names are in the client's own language (4.6).
- **Accepting trades from the addon** (an Accept Loot Trades option): the game doesn't allow it, so it was removed (section 12).
- **Opening a trade by itself** when an item's holder and winner are near each other: the officer left-clicks the item on the Loot tab instead (5.2).

## 12. WoW: Forever platform

The client uses the modern (Retail-style) API, not the Classic one. Presence in the captured API surface (client 1.60.1, build 69893, interface 16001; forever-addon-kit `data/forever_api.json`) confirms a function exists, not how it behaves; what's been confirmed in the beta is below, and `Beta Checks.md` has the rest.

| Need | API |
| --- | --- |
| Master loot | `IsMasterLooter`, `GetNumLootItems`, `GetLootSlotLink`, `GetLootSlotInfo`, `GetMasterLootCandidate`, `GiveMasterLoot`; `GetLootSourceInfo` gives the corpse's GUID |
| Rolls | `/roll` system messages, parsed with the `RANDOM_ROLL_RESULT` format string; `RandomRoll` for the window's button |
| Chat and sync | AceComm-3.0 and ChatThrottleLib over addon messages; `C_EncodingUtil` for compression. There's **no hashing API**, so the ledger's hash is pure Lua. |
| Guild and officers | `GetGuildRosterInfo`, `C_GuildInfo.GuildRoster`, `C_GuildInfo.GuildControlGetRankFlags` (flag 22 is "Has officer privileges") |
| Raid roster and names | `GetRaidRosterInfo`, `UnitGUID`, `GetPlayerInfoByGUID`; `UnitName(unit)` returns the first name and the surname, which the game joins with a space |
| Roles and talents | `UnitGroupRolesAssigned`; talents through `C_ClassTalents.GetActiveConfigID` and `C_Traits` (`GetConfigInfo`, `GetGroupDisplayInfoByTreeID`, `GetTreeNodes`, `GetNodeInfo`, `GetEntryInfo`, `GetDefinitionInfo`), an inspected player's from config `Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID` after `NotifyInspect` and `INSPECT_READY`, with `C_Traits.HasValidInspectData` |
| Item data | `C_Item.GetItemInfo`, `C_Item.GetItemStats`, the item's tooltip (`ITEM_CLASSES_ALLOWED`) |
| Secrets | `canaccessvalue` before reading anything the client may keep secret |
| Trades | `TRADE_SHOW` and the trade events, `InitiateTrade`, `CheckInteractDistance`, `C_Container.PickupContainerItem`, `ClickTradeButton`, `C_TooltipInfo.GetBagItem` (`BIND_TRADE_TIME_REMAINING`), `UI_INFO_MESSAGE` with `ERR_TRADE_COMPLETE` |
| Addons menu | `## AddonCompartmentFunc` in the TOC |

**Confirmed in the beta** (10-12 Oct 2026):
- `/roll` messages are read, and `UnitName` gives the surname second.
- Whispers only reach "Firstname Surname", the form the addon uses.
- Members can read other ranks' officer privileges.
- `GetLootSourceInfo` gives the corpse's GUID; looted BoP items show a trade timer; trading from the Loot tab fills the trade, and finished trades are noticed.
- Master loot is available (with free for all, round robin, group loot and need before greed).
- Every class has exactly one spec (a rogue's is 1488, a druid's 1484, with the role "DAMAGER"), and items have no spec lists, but their type and subtype, stats and a `Classes:` tooltip line are there.
- `C_SpecializationInfo.GetTalentInfo` returns nothing for any talent, own or inspected, hence the trait trees.
- The minimap's addons menu exists and lists the addon but is hidden, hence the minimap button.
- `AcceptTrade` does nothing from an addon (the game marks trade acceptance as restricted).

## Revision history

- **v0.1 (7 Oct 2026)**: initial draft consolidating the design discussion.
- **v0.2 (7 Oct 2026)**: client (WoW: Forever), master loot, out-of-combat only, GUID keying; pity award timing; modifier before clamp confirmed; approximate odds; audit log as source of truth; writer handover; sequential roll windows; new open questions.
- **v0.3 (7 Oct 2026)**: live-updating odds from pool and pity only; multiple copies (top N); upgrade rule parked; duplicates left until needed; Forever API notes.
- **v0.4 (8 Oct 2026)**: open questions decided: not rolling, absence decay, the off-spec penalty, role detection and snapshots, the cap stays at +50, officer ranks, leavers, writer reloads, tied players who don't reroll, per-character pity, horizontal gear, the raw-roll tiebreak and greed wins.
- **v0.5 (9 Oct 2026)**: passing; auto-roll; auto-award; won items awaiting trade; disenchanting unrolled BoP items; options only in the window and account-wide; your chance shown under your roll; rerolls clear the tied players' old rolls; raid chat review (5.3); later features: auto-trade, several items in a row (draft).
- **v0.6 (10 Oct 2026)**: trading won items from the Loot tab, and filling the trade window (most of auto-trade); copies won by their holder aren't awaiting trade; reopened loot isn't added twice; hide loot you can't roll on; minimap button option; entering a raid focuses My pity on it; awaiting trade stays open when loot is added; later features: Gargul popups, letting the raid know about the addon (drafts).
- **v0.6.1 (10 Oct 2026)**: a reroll keeps the tied players' earlier rolls, greyed out; hiding loot keeps the copy you won.
- **v0.7 (10 Oct 2026)**: decisions on the undecided items: no upgrade test; anyone may greed-roll, with no off-spec; Keep to sell for unwanted BoEs; loot kept through reloads; odds worked out by each client; whispered refusals; closing warning; auto-roll rerolls straight away. Ties that settle themselves aren't announced; your own roll shows at once; nothing before 1.0 is migrated. From the beta: who can use an item comes from its type and Classes line; off-spec goes by raid role, with officers able to set an item's roles; accepting trades dropped (the game blocks it); a minimap button; the Roll tab shows rolls you can't join.
- **v0.7.1 (10 Oct 2026)**: the minimap button is made with LibDBIcon; roles limited by class; `/pl test reset` also empties the Loot tab; the beta checks moved to `Beta Checks.md`.
- **v0.7.2 (10 Oct 2026)**: the Loot tab shows an item's roles as the game's role icons; items are described by their roles, not as "main-spec for" them.
- **v0.8 (12 Oct 2026)**: options in profiles (AceDB's), managed from the Options tab; players without a raid role have it guessed from their active spec's capstone talent, told to the writer by their client; borderless role icons on the Loot tab, beside the details.
- **v0.8.1 (12 Oct 2026)**: the writer inspects players without the addon for their capstone; role icons lower and closer together; the window is re-anchored where it's drawn before moving or resizing.
- **v0.8.2 (12 Oct 2026)**: an option to hide tooltips' click hints; even spacing around the Options tab's section titles; the window follows the mouse itself when dragged; role icons nudged.
- **v0.8.3 (12 Oct 2026)**: talents are read from Forever's trait trees, as `GetTalentInfo` returns nothing; capstones recognised by name.
- **v0.9 (12 Oct 2026)**: the Raid tab for officers, with officers able to set raiders' roles; the writer shares its view of the roles; capstones found by their place as each tree's last node.
- **v0.9.1 (12 Oct 2026)**: unknown roles use their class's fallback role in rolls; talents without a capstone count as unknown; why a role is unknown is tracked and shared; Raid tab tooltips reworked.
- **v0.9.2 (12 Oct 2026)**: inspect failures in red on the raider's tooltip, which updates live; Berserk and Rage of the Farseer leave tank or damage for an officer to pick; test raiders with every kind of unknown role, and fake inspects.
- **v0.9.3 (12 Oct 2026)**: raider tooltip reordered and reworded; inspecting shown in light blue with moving dots; certain roles say nothing about their source; Automatic shows an icon.
- **v0.9.4 (13 Oct 2026)**: unchecked roles in light blue rather than red; no "Using the fallback role" lines; warriors fall back to damage (tank only when their talents don't reveal a spec); a sure inspect replaces a role set by hand; Inspect Unknown; members can show the Raid tab to look at; `/pl test reset` clears the Raid tab.
- **v0.9.5 (13 Oct 2026)**: talents that make a role certain come before Blizzard's role menu; the footer is always two lines; later features: localisation with a full text review, and a test menu.
- **v0.10 (13 Oct 2026)**: localisation (5.4): every line players see in `Locales/enUS.lua` (AceLocale, code names); raid chat and whispers stay English (5.3); refusal reasons sent as codes.
- **v0.10.1 (13 Oct 2026)**: capstones are never found by name (talents whose trees can't be told apart are unreadable, and the spellbook isn't used); the document brought up to date section by section: addenda folded into their sections, the odds algorithm moved to 7.5, the API notes and beta results to section 12, open questions trimmed to what's open, and versioned revisions.
- **v0.10.2 (13 Oct 2026)**: a roll that didn't count shows why on your own row for players with the addon, the writer included, who isn't whispered about their own; the footer reads `Rev N by` the officer who recorded it; later feature: verifying revisions.
- **v0.10.3 (13 Oct 2026)**: no more roll-locked: a long run of ties is announced as plain ties, and the header just counts the rerolls.
- **v0.10.4 (13 Oct 2026)**: whispering refused rolls is an officer option of its own (Whisper Refused Rolls), apart from announcing in raid chat; the announcements option's tooltip no longer suggests players' rolls are re-posted.
- **v0.10.5 (13 Oct 2026)**: the project owner's first wording pass in `Locales/enUS.lua`: "raid" for "group" where it means the raid, and a roll's start is just the item and `/roll now`; text codes and the refusal code renamed to match (`MSG_TRADE_NOT_IN_RAID`, `WHY_RAID`, `raid`).
