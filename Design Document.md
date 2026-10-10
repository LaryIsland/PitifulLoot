# Pitiful Loot — Design Document

*Draft v0.2 · Source of truth until v1.0 · Last updated 10 Oct 2026*

**Legend:** **\[Decided\]** = stated by the project owner. **\[Proposed\]** = suggested during design review, not yet confirmed. **\[Open\]** = needs a decision.

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
- Client: **WoW: Forever only**, at least for now. **\[Decided\]**
- Loot method: **master loot**, with officers distributing won items. **\[Decided\]**
- The addon only ever runs **outside of combat**. **\[Decided\]**
- WoW: Forever is realmless and characters carry surnames, so characters are keyed by **GUID**, not by name. **\[Decided\]**

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
| Not rolling | No effect on pity | Decided |
| Leaver decay | -10 pity per week until 0 | Decided |
| Absence decay | None | Decided |
| State authority | Centralised; only officers' copies are authoritative | Decided |
| Source of truth | Audit log of results; pity table is derived from it | Decided |
| Pre-roll odds | Approximate, shown per person in the UI before the roll | Decided |

## 3. Terminology

- **Pity**: a per-character, per-item bonus from 0 to +50 earned by losing rolls on that item.
- **Capped / maxed**: a player at +50 on the item in question.
- **Fresh player**: a player at +0 on the item in question.
- **Modifier**: a roll-time adjustment (currently only the off-spec penalty).
- **Effective roll**: the final number compared between players.
- **Main-spec / off-spec**: whether the item is for the role the player is actually performing in this raid (4.6).
- **Writer**: the single officer who owns the pity table during a raid session (6.2).

## 4. Rules in detail

### 4.1 Pity accrual

- A player gains **+10 pity on an item for every lost roll on it**, up to a **maximum of +50**. **\[Decided\]**
- **Every lost roll counts**: need, off-spec, and any other roll type. **\[Decided\]**
- Pity is awarded **once, after the item has been awarded**: every player who rolled, other than the winner, gains +10. Players eliminated in a tie reroll gain +10 once, not once per round. **\[Decided\]**
- **Not rolling has no effect on pity.** With plain `/roll` there's no pass button, so passing can't be told apart from being AFK or missing the window, and nobody should be punished for those. **\[Decided\]**
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
- Because many rolls clamp to 100 at high pity, ties between capped players are common. Expect several reroll rounds in saturated pools; this is acceptable. Note however that if everyone rolling has the same pity level, you can just accept the highest roll without pity taken into account.
- The same shortcut applies to a **tied subgroup** whose members all have the same effective pity: comparing their original raw rolls gives identical odds to a reroll and saves `/roll` rounds. It does **not** hold when tied players have different effective pity; those must reroll. **\[Decided\]**
- A reroll **ends as soon as every tied player has rolled**, or when its time runs out. From the fourth reroll in a row, the raid is told the players are **roll-locked**, as high-pity players can tie at 100 again and again. **\[Decided\]**
- **Ties that settle themselves stay out of raid chat.** A tie is announced 1.5 seconds after its reroll starts, and only if the reroll is still going. When every tied player rerolls at once (auto-roll), raid chat hears nothing until the result. **\[Decided\]** The 1.5 seconds (to allow for the round trip to the game's server): **\[Proposed\]**
- A tied player who does not reroll before the reroll round closes is dropped from it and loses (they still gain pity, having rolled in the first round). **\[Decided\]**

### 4.3a Multiple copies

- When **two copies** of the same item drop from one kill, the roll works exactly as normal but stops at the **top 2** instead of the top 1; both copies go to those two players and both are locked out of the item. **\[Decided\]**
- Ties only need a reroll when they straddle the cut (for example three players tied for second place); players tied for first and second both win. **\[Decided\]**
- Everyone who rolled and did not win gains +10 pity, as usual. **\[Decided\]**

### 4.4 Winning and the lockout

- A player **may never roll again on an item they have already won** with a need roll. A greed win doesn't lock (4.8). **\[Decided\]**
- A winner may give the item to someone else (for example a friend). They stay locked out of it permanently, so gifting costs them the item. **\[Decided\]**
- Over time the pool for an item shrinks, because each winner removes themselves from it.
- **Duplicate-equippable items** (non-Unique-Equipped items that can fill two slots, such as dual-wield one-handers, rings, trinkets): if any such item exists, the player may roll for a second copy with **pity reset to 0** for that roll, and the first copy must be **equipped** (verified by the addon) so it cannot be traded away. I really doubt such items exist, so this is **deferred to after v1.0 unless one is found**. **\[Decided in principle; implementation deferred\]**

### 4.5 Eligibility

- A player may roll on **every item their class can use** that they want. There's no upgrade test: the addon is need-blind (1.1), so beyond main-spec or off-spec, wanting the item is enough. **\[Decided\]**
- Players cannot roll on items their character cannot use. **\[Decided\]**
- Items that are **nobody's spec in particular** (cosmetics, and anything that isn't gear, such as mounts or recipes) are open to everyone, and nobody is off-spec for them. **\[Decided\]**
- Eligibility is derived from item and spec data, not officer judgement, so there are no "sensible gear" arguments. **\[Decided\]**
- **Concern:** item and spec data may not be good enough to tell who can use an item (or which specs it suits), so officers may need to decide, especially the first time an item drops. Not decided until the beta shows how good the data is (10.3). A possible approach: the first time an item is rolled for, the writer sees which classes and specs the data gives and can correct them; the correction goes in the ledger, so every client applies it and later drops reuse it. **\[Open\]**

### 4.6 Main-spec and off-spec

- The role a player rolls as is **whatever they are actually doing in the raid**: tanking means rolling as a tank, DPS means rolling as DPS. Still allowing rolls for off role gear but with the off-spec penalty. **\[Decided\]** 
- Pity is per item, so switching roles between raids does not change a player's pity; only the -20 offset applies when the item is not for the current role. **\[Decided\]**
- The role is detected by the writer's client **inspecting each raider's spec** and comparing it with the specs the item suits (`C_Item.GetItemSpecInfo`). The writer can flip any roll's off-spec flag before the first round closes. **\[Decided\]** Whether Forever's item spec lists separate tank from DPS gear is to be checked in the beta (10.3).
- To stop spec-swapping to dodge the penalty, the spec is **fixed the first time the writer sees it each raid**. A genuine mid-raid role swap is handled by the writer flipping the flag. **\[Decided\]**

### 4.7 New players

- A new player starts at **0 pity on every item**. **\[Decided\]**
- They are expected to be mostly locked out of heavily contested items but always keep a nonzero chance (see 7.3).
- Their position improves over time as pity accrues, and veterans win and lock themselves out of each item, and at the start of a new tier, when everyone is at 0.

### 4.8 BoE items

- First a **need roll** for players who need the item for gear. **\[Decided\]**
- If nobody needs it, a **greed roll**. **\[Decided\]**
- Pity rises for greed rollers **only if the greed roll actually happens**. **\[Decided\]**
- greed-roll pity is held in a **separate counter** and can never be used as need-roll pity. **\[Decided: accepted as sensible\]**
- **Winning a greed roll doesn't lock the winner out** and changes none of their pity, so they can still need-roll the item if it becomes an upgrade. **\[Decided\]**
- **Everyone may greed-roll**, whatever their class and even if they've won the item. **\[Decided\]**
- **There's no off-spec on a greed roll**: greed is purely for gold or materials. **\[Decided\]**
- A BoE **no one greed-rolls on is kept and sold** (it's worth more on the auction house than disenchanted): the writer's **Keep to sell** button, and the master looter takes it. Nothing is recorded. **\[Decided\]** The button's wording: **\[Proposed\]**

### 4.9 Decay and leaving

- **Leavers**: a player who leaves the guild loses **10 pity per week until 0**, so they can rejoin but at a cost. Applies to every item. The -10 decay happens every 7 days after leaveing, not on the day of leaving **\[Decided\]**
- Leaving and rejoining are **recorded automatically**. Officers' clients compare the guild roster with the ledger. The online officer with the highest rank (then first by name) records the change; the others wait longer, in that order, and only step in if it still hasn't been recorded. Decay counts from when the leave was first seen. Officers can also record either by hand. **\[Decided\]**
- **Absent members** (still in the guild) **don't decay**: pity only ever rewards waiting, and there's no attendance to record. **\[Decided\]**

### 4.10 New tiers and horizontal gear

- New-tier items start at 0 for everyone (a consequence of per-item pity); old-tier pity stays but is moot.
- Gear is expected to become more horizontal, so more players will want each piece and pools will be larger, which makes the new-player odds in 7.3 worse. This is accepted as covered by class-eligibility plus once-per-item, and will be **reviewed after the first tier** (raids open 9 Dec 2026) using real pool sizes from the ledger. **\[Decided\]**

## 5. Roll flow and UI

### 5.1 Flow

1. An item drops. The writer officer opens a roll window, announced in raid chat so players without the addon see it. Windows run **one item at a time**, because a plain `/roll` cannot say which item it is for.
2. Eligible players (class-eligible, not previously winners of the item) roll with `/roll` (1-100).
3. Only the **first roll per player per window** counts; extra rolls are flagged. Rolls outside the window are ignored; rolls with a range other than 1-100 are rejected. **\[Decided\]**
4. The writer closes the window in raid chat and publishes the list of accepted rolls. Clients check each against the rolls they observed themselves.
5. The writer computes effective rolls and resolves any ties by rerolling among the tied players.
6. The winner is announced with the full breakdown, and an officer distributes the item via master loot. If the item can't be given by master loot, it is traded to the winner and listed as awaiting trade until the trade goes through (5.2); if the winner is the officer who looted it, they already have it and nothing is listed. A BoP item no one rolled on is disenchanted instead: nothing is recorded, and the master looter takes it; a BoE no one greed-rolled on is kept to sell (4.8). **\[Decided\]**
7. Once the item is awarded, every player who rolled, other than the winner, gains +10 pity on the item (to a maximum of +50).
8. The result is appended to the audit log and the updated pity table is published with a revision number and hash (6.3).

### 5.2 UI requirements

- **Pre-roll odds per person** are shown before the roll. **\[Decided\]** They only need to be **approximate**; the actual outcome is what matters. The pool is assumed to be the players who already have pity on the item. Odds use the same tie-reroll mechanism as the real roll (see Appendix A) and include the off-spec modifier. **\[Decided\]**
- The odds **update live**: when a roll is seen from a player not already in the assumed pool, they are added. Odds use only **who is in the pool and their effective pity**, never the values already rolled. This is safe because rolling can only ever help a player, whatever the other rolls are. **\[Decided\]**
- **Every client works out the odds itself**, from the same seed (Appendix A), so everyone sees identical numbers without the writer sending them: less addon traffic. **\[Decided\]**
- Roll results show a breakdown in raid chat (5.3). **\[Decided\]**
- The pity table is visible to everyone with the addon. **\[Decided\]**
- Hiding rolls from other players is **not needed**: rolling is free and a roll cannot be changed after it is seen. **\[Decided\]**
- While a player can roll, **their own row sits at the top of the roll page with "Click to roll"** across it, which does the `/roll 1-100` for them, with their chance of winning on the right; typing `/roll` still works the same. Their own row is always highlighted. A roll a player can take part in opens the window on the Roll tab (a setting turns this off). **\[Decided\]**
- **The loot is shared with the whole group.** The officer who loots the boss (the master looter) sends the item list, and everyone's Loot tab shows each item's roll: rolling, won, awarded (greyed out, with the winners' names) or no one rolled, plus their own pity on it when they have some. Each boss's loot is a group headed by the boss, in the order it was seen; new loot opens its group and the items awaiting trade, folds the other groups away, and opens the window on the Loot tab (a setting turns this off). Opening the same corpse again never adds its loot twice, even once some of it has been handed out (the corpse's GUID identifies it, or failing that the same items). A setting hides the items you can't roll on (your class can't use them, or they're a later drop of an item you've won; the copy you won stays, and BoEs always show, as anyone can greed-roll them), and then loot that's all like that doesn't open the window. Only the writer can start rolls from it: left-click an item for a roll, right-click a BoE for a greed roll, as its tooltip says. **\[Decided\]** The writer always sees everything, even with that setting on, as rolls are started from it; and loot that's all hidden doesn't open the window. **\[Decided\]**
- In a reroll, the tied players have their own section above everyone else, during the reroll and after it; players out of it keep their roll and their odds from before the tie. **\[Decided\]**
- The **My pity** list shows, next to each item's pity, how much better your odds are than with no pity, one on one (from 7.1). **\[Decided\]**
- The window has an **Options tab** (always the bottom tab) holding all the options. Options for running rolls are hidden unless an officer ticks **Officer options** in its corner; members never see them.
- **Every player's name is shown in their class colour.** **\[Decided\]**
- Announcements are plain sentences without the addon's name, to keep them easy to skim. They go to **raid chat** (party chat in a party), never `/say`, so everyone in the group sees them with or without the addon. When the writer is raid leader or an assistant, the headlines (a roll starting, a tie, the result, no rolls) are **raid warnings**; breakdowns stay in raid chat. A setting turns raid warnings off. **\[Decided\]**
- The **My pity** list is grouped under the raid each item drops in, with a setting to group by boss inside each raid. Groups collapse. Entering a raid opens its group (bosses included) and folds every other raid away; after that the groups stay as you leave them until you next enter a raid. Where an item drops is recorded with each roll (the writer's instance, and the boss last killed there); items with no recorded source go under Other. A setting hides items you've won. **\[Decided\]**
- **Your chance goes under your roll.** The large figure on the right of a row is only ever the roll's total; the chance to win sits under it. Your own row shows your chance before you roll even if you have no pity (worked out with you added to the pool, on your client only, so everyone else's figures still match every other client's). **\[Decided\]**
- **Your roll shows as soon as you make it.** Your row stays at the top from the moment you click until the game says what you rolled, then shows that roll where the writer's count will put it, without waiting the half second for the writer's message. **\[Decided\]**
- **Passing.** Your row has the group loot roll's pass button in its top right corner, apart from the rest of the row, which rolls. Passing changes nothing in the ledger (not rolling never does), but it takes you out of everyone's odds, shows you as passed, stops auto-roll, and ends a reroll sooner (a reroll ends once every tied player has rolled or passed). A `/roll` after passing still counts. Passes aren't announced in raid chat. A pass button, apart from the click that rolls, its place, and what passing does: **\[Decided\]**
- **In a reroll**, the tied players' earlier rolls stay on their rows, greyed out, until they roll again, so the tie can still be seen but new and old numbers aren't confused; players who have rerolled come first. **\[Decided\]**
- **Won items awaiting trade** are listed at the top of the Loot tab, one row per copy: every one for officers, and your own for you. Each shows who it's for and who has it, and the time left to trade it (red under 30 minutes). Either side's client sees the trade go through and tells the group, so everyone's list stays current; officers can also right-click one to mark it handed over. An officer holding a copy left-clicks it to open a trade with the winner (or is told they're too far away); whenever a trade opens between them, whoever opened it, the copies the officer holds for the winner go in, a copy still inside its trade window first. A trade that goes through is checked off automatically; marking by hand is the fallback. Copies given by master loot, and copies won by the officer who looted them, are never listed. **\[Decided\]**
- **Trades are finished by hand**: a person clicks Trade on each side. The exception is the general option **Accept Loot Trades** (off by default), which clicks Trade for you on a trade that is only a handover: you give only copies owed to the other player and get nothing back, or you get only copies you won and give nothing, with no gold either way. **\[Decided\]** Only officers' clients putting items in (so a member's own copy of the same item is never offered), and taking `traded` only from officers or the winner: **\[Proposed\]**
- **Loot is kept through a /reload or logging out**, per character, and after leaving the group while copies are still to be handed over, so nothing awaiting trade is lost. Loot older than the trade window is dropped; out of a group, so is loot with nothing left to hand over. A late joiner still gets the writer's copy. **\[Decided\]**
- **After an award or a disenchant**, the writer is taken back to the Loot tab while there's loot left to roll for or hand over, copies awaiting trade included, and after an automatic award too. **\[Decided\]**
- **Options** are only on the window's Options tab (no page in the game's settings), and are account-wide: the same for every character. General options: auto-roll (off by default; rerolls only, which rolls straight away, or every roll, which waits 5 seconds in a new roll so you can pass), accept loot trades, open the window when you can roll, open it on the Loot tab when loot is added (on by default for everyone), hide loot you can't roll on, group My pity by boss, hide won items, and the minimap button (the entry in the minimap's addons menu; `/pl` opens the window either way). Officer options: announcements, raid warnings, roll and reroll times, loot quality, and awarding automatically. **\[Decided\]**

### 5.3 Raid chat messages

Reviewed 9 Oct 2026. All go to raid chat (party chat in a party); "headline" ones are raid warnings when the writer may send them.

| When | Message | Headline |
| --- | --- | --- |
| An officer becomes the writer | `Ofelia is running loot rolls.` | |
| Another officer takes over a roll | `Bram has taken over the roll for [Item].` | |
| A roll starts | `Roll for [Item]: /roll now (30s).` with `(2 copies)` or `Greed roll for` as needed | Yes |
| A tie | `Tie for [Item] between Lary, Tobin: /roll again (20s).` | Yes |
| A tie after some copies are won | `Tobin wins [Ring].` then `Tie for the last copy of [Ring] between Mira, Lary: /roll again (20s).` | The tie |
| From the fourth reroll in a row | `Roll-locked! Reroll 4 for [Item] between Lary, Tobin: /roll again (20s).` | Yes |
| The result | `[Item] goes to Mira.` | Yes |
| Each winner's breakdown | `Mira: 90`, `Lary: 62 + 50 pity - 20 off-spec = 92`, `Lary: 62 + 50 pity = 100 (max)`, with `(reroll)` for a reroll | |
| No one rolled | `No one rolled for [Item].` | Yes |
| A roll is cancelled | `The roll for [Item] was cancelled.` | |
| A BoP item no one rolled on | `[Item] will be disenchanted.` | |
| A BoE no one greed-rolled on | `[Item] will be sold.` | |
| 5 seconds before the opening round closes | `5 seconds left to /roll for [Item].` | |
| A refused roll, from a player without the addon (a whisper, once per roll) | `Your roll for [Item] didn't count: already won this item.` | |

A tie is held back for 1.5 seconds and dropped if everyone has rerolled by then (4.3), so instant rerolls don't fill raid chat.

Changed in the review: breakdowns no longer say `pity +0` or `roll`, and say when the clamp at 100 cut a total; a tie with copies already won names those winners first. **\[Decided\]**

Decided on 10 Oct 2026: **\[Decided\]**
- Refused rolls are whispered to players without the addon, once per roll, with the reason. The writer knows who has the addon because every client answers a new writer, and anything a client sends counts.
- A last call 5 seconds before the opening round closes, in raid chat (not a raid warning). Closing the round once every eligible player has rolled or passed (Later features) would make it rarer.
- No message saying a greed roll is next after no one needs a BoE.

## 6. Authority, trust and data sync

### 6.1 Central state

- Pity state is **centralised**. Only officers' copies are authoritative; discrepancies between officers are investigated. **\[Decided\]**
- Everyone else's copy is a read-only cache for their own reference and for catching discrepancies. **\[Decided\]**
- The **audit log is the source of truth**; the pity table is derived from it by replaying the log. **\[Decided\]**
- Outcomes are derived from the **recorded `/roll` chat results**, never from addon-side random numbers. `/roll` results are server-generated system messages that players cannot forge, and the raid sees them, so every client with the addon can independently verify each logged result. **\[Decided\]**
- Rule changes that alter pity outside a roll (leaver decay, absence decay, officer corrections) are recorded as dated log entries, so replaying the log always reproduces the same table. **\[Decided\]**

### 6.2 Single writer

- One officer is the **writer** for each raid session; other officers hold read-only mirrors and reconcile after the raid. This avoids two officers writing conflicting results. **\[Decided\]**
- If the writer leaves, disconnects or reloads mid-roll, **another officer takes over** as writer, carrying on from their own copy of the roll. **\[Decided\]**

### 6.3 Publishing the pity table

- The pity table is **published to everyone with the addon**. **\[Decided\]**
- **Only officers can push updates**, and clients accept updates **only from officers**. **\[Decided\]**
- The game stamps the real sender name on addon messages, so "is the sender an officer" can be checked against guild rank. **\[Decided\]**
- **Officers are the guild ranks given officer privileges in the guild's own rank settings** ("Has officer privileges", what the game itself means by an officer), so every client agrees without any setting. The guild master always counts. If a client can't read the rank settings, ranks 0 and 1 count. **\[Decided\]**
- Sharing uses a **two-way handshake**, so a tampering sharer's name is very obvious. **\[Decided\]**
- A tampered client only changes what that player sees; it cannot change an outcome. **\[Decided: accepted risk\]** The real risk is a tampered *officer* client. But auditing from every other player in the raid with the addon should catch that instantly.
- Each update carries a **revision number and a hash of the full table**. Officers compare hashes to detect divergence, and clients display "rev N published by Officer X, verified". **\[Decided\]** Implemented as a hash chain: the revision is the number of log entries, and each entry carries the hash of the one before it, so the head hash covers the whole history and therefore the table.
- The hash detects **divergence, not authenticity**: a tampering officer can produce a valid hash for a fake table. Authenticity comes from every client checking each new log entry against the rolls it observed. **\[Decided\]**
- An **audit log** records each result: all rolls, modifiers, and pity before and after. **\[Decided\]**

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

The 12% in the design tenets holds only against **one** capped player. This is the worst case; it eases as winners remove themselves from the pool and resets at tier launch. It was the main question for whether the cap should drop to +40; the cap stays at +50 (decided 8 Oct 2026).

### 7.4 If the cap were lower (not adopted)

| Cap | Capped vs fresh | New player vs 1 / 3 / 8 capped |
| --- | --- | --- |
| +50 (current) | \~88% | 12.4% / 1.6% / 0.03% |
| +40 | \~82% | 17.9% / 3.3% / 0.15% |
| +30 | \~76% | 24.4% / 6.0% / 0.5% |

## 8. Exploit review

| Concern | Disposition |
| --- | --- |
| Rolling on everything to farm pity | Not possible: pity is per item and players can only roll on items usable and sensible for their character. |
| Alts and extra characters | Pity is per character, so playing one character means not playing another; alts accrue pity slower. **\[Decided\]** |
| Win then give the item to a friend | Allowed. The winner is locked out of that item permanently. |
| BoE and vendor items | Raid drops are BoP. BoE: need roll first, then greed roll with a separate pity counter. |
| Seeing rolls before committing | Irrelevant: rolling is free and rolls cannot be changed. |
| Tampering with pity state | Centralised officer-held state; clients accept only officer updates; hashes and audit log (6). |
| Spec-swapping to dodge the off-spec penalty | Spec fixed when the writer first sees it each raid; the writer can flip a roll's flag. **\[Decided\]** |
| Spamming rolls or odd roll ranges | First roll per window only; reject non-1-100 ranges. **\[Decided\]** |
| Returning with stale high pity | Accepted: pity rewards waiting, and only leaving the guild decays it (4.9). **\[Decided\]** |
| Passing an item to dodge the lockout (duplicates) | Pity reset plus first copy must be equipped. **\[Deferred\]** (confirmed 10 Oct 2026) |

## 9. Accepted shortcomings (explicitly decided)

- **Pity saturates after 5 losses.** If 8 people have all waited around two months for an item, everyone ends up at +50 and someone has to win; it becomes a lottery among long-waiters. **\[Decided\]**
- **New players are mostly locked out** of contested items (7.3), but never completely. **\[Decided\]**
- **Need-blind**: no weighting by how big the upgrade is. **\[Decided\]**
- **No cross-item fairness**: a player can win several items in a run. To reach five items at +50 they must have lost every one of them repeatedly. **\[Decided\]**
- **Pity is not a guarantee**: a +50 player still loses about 12% of the time to a fresh player, and half the time to another +50 player.
- **Off-spec pity accrues at the full rate**, so a long-waiting off-spec player (+50 less 20 = +30) beats a fresh main-spec player about 76% of the time. **\[Decided\]**
- **Diminishing returns** from the clamp at 100: the first +10 adds about 10 points of win chance, the last about 6.

## 10. Open questions

Decided on 8 Oct 2026, in the sections above: not rolling, absence decay, the off-spec penalty, role detection and snapshots, the cap, officer ranks, leavers, writer reloads, tied players who don't reroll, per-character pity, horizontal gear, the raw-roll tiebreak and greed wins. What's left:

1. Duplicate-equippable item handling: build only if it actually comes up (`C_Item.GetItemUniqueness` can detect candidates).
2. Whether item and spec data is good enough to decide eligibility, or officers need a say (4.5).
3. Runtime behaviour to confirm in the beta client (the beta checklist page collects the results):
   - roll system messages arrive and parse as expected;
   - inspected specs are readable (not secret) out of combat;
   - what `C_Item.GetItemSpecInfo` lists, in particular whether DPS items also list tank specs (4.6);
   - whether ordinary members' clients can read other ranks' officer privileges (6.3);
   - addon messages are not restricted;
   - `UnitName` gives the surname as its second value (as Forever's own UI assumes), and roll messages show the full name;
   - what names master loot candidates and addon message senders carry (with or without the surname);
   - a looted BoP item can be traded for two hours (assumed, as on Retail), and a finished trade sends `ERR_TRADE_COMPLETE` as a `UI_INFO_MESSAGE`;
   - a tradeable BoP item's tooltip carries `BIND_TRADE_TIME_REMAINING`, and picking an item up from the bags then `ClickTradeButton` puts it in the trade without a hardware click;
   - `GetLootSourceInfo` gives the corpse's GUID while it's looted (used to tell reopened loot from new loot);
   - adding the addon to the minimap's addons menu at runtime (`AddonCompartmentFrame:RegisterAddon`) and taking it out again works, and taints nothing;
   - `AcceptTrade` works from an addon without a click (for Accept Loot Trades);
   - a whisper reaches a player addressed by the full name their roll message shows (with the surname).
4. Addon message limits. Messages go through AceComm and ChatThrottleLib, which pace them by bandwidth and retry any the client reports as throttled; live roll messages go out before ledger sync. The harness assumes the client allows 10 messages at once per prefix, then 1 a second. If that's right, live rolls fit (they're batched), but a first full ledger sync is slow (roughly 250 bytes a second per officer, after compression). Measure in the beta.

### Later features (agreed, not yet built)

- **Raid management tab**, for officers only: every raider and the role they're currently down as (tank, healer or damage), in sections with dividers between them.
- **End the opening round early** once every eligible player in the raid has rolled, as rerolls already do. Needs a reliable idea of who is eligible (class, spec, lockouts, and whether someone simply doesn't want the item), so it isn't built yet. Passing (5.2) now covers "doesn't want it" for players with the addon.
- **Auto-trade (before v1.0).** When a won item is awaiting trade and its holder is near the winner, open a trade with the winner and put the item in it; and when the winner opens a trade with the holder, put the item in. It never accepts the trade: the last click is always by hand, unless that player turned on Accept Loot Trades (5.2). **\[Decided\]** Built on 10 Oct 2026, except opening the trade by itself when the two are near each other: the officer left-clicks the item on the Loot tab instead (5.2).
- **Several items in a row (draft, not agreed).** Rolls stay one item at a time, as a plain `/roll` can't say which item it's for; this is about running them back to back. **\[Proposed\]**
  - *Roll all*: a button on each boss's loot header, for the writer, that queues every item in it still to roll for, in loot order, need rolls before greed rolls.
  - *Queue*: shift-clicking an item on the Loot tab adds it to the queue instead of starting it; the queue shows as numbered badges on the items, and right-clicking a queued item takes it off.
  - *Running the queue*: the next roll starts a few seconds after the last is awarded or disenchanted, and raid chat says where it's got to (`Roll for [Item] (2 of 5): /roll now (30s).`). Ties pause the queue until they're settled. Award Automatically makes it run unattended; without it, it waits for each Award. A BoP item no one rolls on is left for the writer to disenchant (or disenchanted automatically, as an option) and the queue moves on.
  - *Safety*: Cancel stops the current roll and asks whether to stop the queue too; the queue goes in the writer's state reply, so an officer taking over carries on with it.
  - *Not proposed*: rolling several items at once with different roll ranges (`/roll 101-200` for the second item), which breaks "just /roll" (1.1) and the 1-100 rule.
- **Gargul popups for raiders without Pitiful Loot (draft, not agreed).** Raiders who run Gargul but not Pitiful Loot should get Gargul's own roll popup when a roll starts, and its "you won" notice on an award, as if Gargul were running the loot. **\[Proposed\]**
  - *What Gargul does* (read from Gargul 8.0.1's source, 10 Oct 2026; not tried in game). It has a Forever build. Its messages use the prefix `GargulComm2`, packed with LibSerialize and LibDeflate. Starting a roll shows every Gargul user a popup with one button per roll range the sender lists (each does a `/roll` in that range) and a Pass button; it doesn't check who sent it. Stopping one is only accepted from whoever started it, and an award gives the winner the game's "You won" toast and adds it to everyone's Gargul history. Gargul doesn't react to raid chat or raid warnings, so today Gargul users only see Pitiful Loot's announcements in chat.
  - *How*: the writer's client sends Gargul's own "start roll" message when a roll or reroll starts, with a single **Roll (1-100)** button (Gargul's default off-spec 1-99 roll would be refused, 5.1), the time left, and a note (`Pity roll` or `Reroll: Lary, Tobin only`); its "stop" when the round closes; and its "award" when the roll is awarded. An officer option turns it off.
  - *Risks*: this copies Gargul's internal message format, which has no promise of staying the same (its message numbers changed recently), so a Gargul update can quietly break it; it needs two more libraries; players running both addons get two popups unless Pitiful Loot asks Gargul to skip them, which it can't. A safer but narrower alternative: when the writer also has Gargul, call the functions Gargul offers other addons (`Gargul.RollOff:announceStart`), though that only works for writers with Gargul installed and makes Gargul post its own chat lines too.
  - *Recommendation*: copy the message format, check it against each Gargul release, and switch it off by itself if Gargul's minimum version moves past the one it was built for.
- **Letting the raid know Pitiful Loot exists (draft, not agreed).** Players without the addon only see plain raid chat (5.3), which never names the addon. A quiet way to tell them, without nagging anyone. **\[Proposed\]** Options:
  1. *Whisper once*: the first time someone `/roll`s in a roll without the addon, the writer's client whispers them one line, at most once per player: `These rolls use Pitiful Loot: each roll you lose on an item adds pity to your next roll on it. /roll is all you need; the addon shows your pity and odds.` Needs to know who has the addon: clients answer a short "here" when a writer takes over.
  2. *Name it once per raid* in the line that already says who's running loot: `Ofelia is running loot rolls with Pitiful Loot.` One line a night, seen by everyone, including people who already know.
  3. *Leave it to the breakdowns*: results already say `62 + 50 pity = 100`, which invites the question. Costs nothing, but tells no one where to look.
  - *Recommendation*: 1, as it only reaches people who don't have the addon, once each, privately; with 2 as the fallback if whispers feel too pushy.

## 11. Alternatives considered, not adopted

- **Strict tiers** (any main-spec roller beats any off-spec roller): breaks the new-player tenet for off-spec rolls.
- **Hard pity** (guaranteed win after N losses): the soft system was preferred.
- **Uncapped `d100 + pity`** (no clamp at 100): would remove mass ties and the diminishing returns, but was not chosen.
- **Cross-item penalties** for recent winners: rejected; sweeping several items is acceptable.
- **Hiding rolls until all are in**: unnecessary since rolling is free.

## Appendix A: Odds algorithm

For each player, effective pity `e = pity + modifier`. Each player's roll distribution is `min(d + e, 100)` for `d = 1..100`.

`P(i wins)` for a pool = sum over each value `v` that `i` can roll of `P(i rolls v)` times:

- `P(every other player rolls below v)`, plus
- for each non-empty subset `S` of the others who tie at `v` (the rest rolling below): the probability of that outcome times `W(i, S)`, where `W` is the same calculation applied recursively to the sub-pool `{i} ∪ S` (reroll, pity retained).

Players with the same effective pity are interchangeable, and effective pity takes only a handful of values (-20 to +50 in steps of 10), so memoise on the count of players at each value; this keeps an exact calculation cheap. Alternatively, run 20,000-50,000 simulated rolls. Displayed odds only need to be approximate (5.2), so either approach is acceptable, but both must model the same tie-reroll mechanism as the real roll.

Implemented as simulation: 10,000 trials through the real ranking code, spread over frames (1,000 per frame), seeded from the pool's composition so every client shows identical figures. Players with the same bonus share one figure. Pools where everyone has the same bonus, or with as many copies as players, are exact (`copies / players`).

Validation: the exact recursion matched simulation (for example, a new player against 3 capped players: 1.58% exact versus 1.59% simulated).

## Appendix B: WoW: Forever API notes

From the captured Forever client API surface (client 1.60.1, build 69893, interface 16001; forever-addon-kit `data/forever_api.json`). Presence in the dump confirms a function exists, not how it behaves. The client uses the modern (Retail-style) API, not the Classic one.

| Need | API |
| --- | --- |
| Loot method | `C_PartyInfo.GetLootMethod` (the global `GetLootMethod` is gone), `IsMasterLooter` |
| Master loot | `GetNumLootItems`, `GetLootSlotLink`, `GetLootSlotInfo`, `GetMasterLootCandidate`, `GiveMasterLoot` |
| Rolls | `/roll` system messages, parsed with the `RANDOM_ROLL_RESULT` format string |
| Chat and sync | `C_ChatInfo.SendChatMessage`, `C_ChatInfo.RegisterAddonMessagePrefix`, `C_ChatInfo.SendAddonMessage`, `C_ChatInfo.InChatMessagingLockdown`, `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted` |
| Serialisation | `C_EncodingUtil` (CBOR, JSON, compression, Base64, hex). There is **no hashing API**, so the table hash needs a pure-Lua implementation. |
| Guild and officers | `GetGuildRosterInfo`, `GuildControlGetRankName`, `C_GuildInfo.GuildRoster`, `C_GuildInfo.IsGuildOfficer`, `C_GuildInfo.GuildControlGetRankFlags` |
| Raid roster and identity | `GetRaidRosterInfo`, `UnitGUID`, `GetPlayerInfoByGUID`, `C_PlayerInfo.ShouldDisplaySurname` |
| Role and spec | `UnitGroupRolesAssigned`, `C_SpecializationInfo.GetSpecialization`/`GetSpecializationInfo`/`GetInspectSpecialization`, `NotifyInspect` |
| Item data | `C_Item.GetItemInfo`, `C_Item.GetItemSpecInfo` (specs an item suits), `C_Item.DoesItemContainSpec`, `C_Item.IsEquippedItem`, `C_Item.GetItemUniqueness` |
| Combat and secrets | `InCombatLockdown`, `issecretvalue`, `C_Secrets` |
| Trades | `TRADE_SHOW`, `TRADE_CLOSED`, `TRADE_PLAYER_ITEM_CHANGED`, `TRADE_TARGET_ITEM_CHANGED`, `TRADE_ACCEPT_UPDATE`, `GetTradePlayerItemLink`, `GetTradeTargetItemLink`, `UnitGUID("NPC")` (the other player), `UI_INFO_MESSAGE` with `ERR_TRADE_COMPLETE`, `InitiateTrade`, `CheckInteractDistance`, `C_Container.PickupContainerItem`, `ClickTradeButton`, `C_TooltipInfo.GetBagItem` |
| Loot source | `GetLootSourceInfo` (the corpse's GUID) |
| Addons menu | `AddonCompartmentFrame:RegisterAddon`, and its `registeredAddons` list to take an entry out (Forever uses Retail's compartment; it has no way to remove one) |
| Names | `UnitName(unit)` returns the first name and the surname; the game joins them with a space (`NameUtil.FormatUnitNameForDisplay`) |

Forever has Retail-style specialisations, so main-spec and off-spec can likely be decided per item with `C_Item.GetItemSpecInfo` against the player's current spec. This bears on open question 4.

## Revision history

- **v0.1 (7 Oct 2026)**: initial draft consolidating the design discussion.
- **v0.2 (7 Oct 2026)**: client (WoW: Forever), master loot, out-of-combat only, GUID keying; pity award timing; modifier before clamp confirmed; approximate odds; audit log as source of truth; writer handover; sequential roll windows; new open questions 8-10.
- **v0.3 (7 Oct 2026)**: live-updating odds from pool and pity only; multiple copies (top N); upgrade rule parked; duplicates left until needed; Appendix B (Forever API notes).
- **9 Oct 2026**: passing; auto-roll; auto-award; won items awaiting trade; disenchanting unrolled BoP items; options only in the window and account-wide; your chance shown under your roll; rerolls clear the tied players' old rolls; raid chat review (5.3); later features: auto-trade, several items in a row (draft).
- **10 Oct 2026**: trading won items from the Loot tab, and filling the trade window (most of auto-trade); copies won by their holder aren't awaiting trade; reopened loot isn't added twice; hide loot you can't roll on; minimap button option; entering a raid focuses My pity on it; awaiting trade stays open when loot is added; later features: Gargul popups, letting the raid know about the addon (drafts). Later the same day: a reroll keeps the tied players' earlier rolls, greyed out; hiding loot keeps the copy you won.
- **10 Oct 2026 (later)**: decisions on the undecided items: no upgrade test; anyone may greed-roll, with no off-spec; Keep to sell for unwanted BoEs; Accept Loot Trades option; loot kept through reloads; odds worked out by each client; whispered refusals; closing warning; auto-roll rerolls straight away; officer say on eligibility left open. Then: ties that settle themselves aren't announced; no "Your pity +0"; your own roll shows at once; no settings migration (nothing before 1.0 is migrated).
