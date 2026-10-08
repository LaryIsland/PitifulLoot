# Pitiful Loot — Design Document

*Draft v0.2 · Source of truth until v1.0 · Last updated 7 Oct 2026*

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
- Gear in future tiers is expected to be more horizontal (see 4.10). **\[Decided as context; handling is Open\]**
- Client: **WoW: Forever only**, at least for now. **\[Decided\]**
- Loot method: **master loot**, with officers distributing won items. **\[Decided\]**
- The addon only ever runs **outside of combat**. **\[Decided\]**
- WoW: Forever is realmless and characters carry surnames, so characters are keyed by **GUID**, not by name. **\[Decided\]**

## 2. Rules at a glance

| Rule | Value | Status |
| --- | --- | --- |
| Pity gain | +10 per lost roll, on that item only | Decided |
| Pity maximum | +50 (working value; +40 is the alternative) | Open |
| Effective roll | `min(d100 + pity + modifier, 100)` | Decided |
| Off-spec modifier | -20 (working value; -10 is the alternative) | Open |
| Tie | Reroll among tied players only, pity retained | Decided |
| New player | Starts at 0 on every item | Decided |
| Winning | Does **not** reset pity; you may never roll on that item again | Decided |
| Lost rolls counted | All of them, including off-spec and any roll type | Decided |
| Pity award timing | Once, after the item is awarded, +10 to everyone who rolled except the winner | Decided |
| Passing | Whether passing affects pity | Open |
| Leaver decay | -10 pity per week until 0 | Decided |
| Absence decay | None, or -10 per month (undecided) | Open |
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
- Whether **passing** leaves pity unchanged or resets it on that item. **\[Open\]**
- Pity accrues at the **full rate on off-spec rolls**; off-spec rollers do not accrue more slowly. A tank who has to play DPS for a raid should not take both a roll penalty and slower pity. **\[Decided\]**
- Pity is tracked per **item ID**. **\[Decided\]**
- Pity is tracked **per character**, keyed by character GUID. This is implied by the alt discussion (alts are disincentivised because pity accrues slower when your attendance is split). **\[Open: confirm per-character\]**
- Pity on one item can never affect another item. **\[Decided\]**

### 4.2 Effective roll

`effective = min(d100 + pity + modifier, 100)`

- `pity` is 0 to +50. `modifier` is 0 for main-spec and **-20 for off-spec** (working value). **\[Open: -10 versus -20\]**
- The modifier is applied **before** the clamp at 100, so it reads as "two lost rolls behind". **\[Decided\]**
- **No floor** on effective pity or on the effective roll: effective pity runs from -20 to +30 for off-spec. **\[Proposed\]** Flooring effective pity at 0 would make a fresh off-spec player exactly as strong as a fresh main-spec player and remove the penalty for anyone below +20 stored pity.
- The clamp wastes overflow: each pity step is worth less than the one before it (see 7.1).

### 4.3 Ties

- Players tied on the highest effective roll **reroll among themselves only**, retaining their pity, until one player is strictly highest. **\[Decided\]**
- Because many rolls clamp to 100 at high pity, ties between capped players are common. Expect several reroll rounds in saturated pools; this is acceptable. Note however that if everyone rolling has the same pity level, you can just accept the highest roll without pity taken into account.
- The same shortcut applies to a **tied subgroup** whose members all have the same effective pity: comparing their original raw rolls gives identical odds to a reroll and saves `/roll` rounds. It does **not** hold when tied players have different effective pity; those must reroll. **\[Proposed; implemented\]**
- A tied player who does not reroll before the writer closes the reroll round is left out of it. **\[Proposed\]**

### 4.3a Multiple copies

- When **two copies** of the same item drop from one kill, the roll works exactly as normal but stops at the **top 2** instead of the top 1; both copies go to those two players and both are locked out of the item. **\[Decided\]**
- Ties only need a reroll when they straddle the cut (for example three players tied for second place); players tied for first and second both win. **\[Proposed\]**
- Everyone who rolled and did not win gains +10 pity, as usual. **\[Decided\]**

### 4.4 Winning and the lockout

- A player **may never roll again on an item they have already won**. **\[Decided\]**
- A winner may give the item to someone else (for example a friend). They stay locked out of it permanently, so gifting costs them the item. **\[Decided\]**
- Over time the pool for an item shrinks, because each winner removes themselves from it.
- **Duplicate-equippable items** (non-Unique-Equipped items that can fill two slots, such as dual-wield one-handers, rings, trinkets): if any such item exists, the player may roll for a second copy with **pity reset to 0** for that roll, and the first copy must be **equipped** (verified by the addon) so it cannot be traded away. I really doubt such items exist, so this is **deferred to after v1.0 unless one is found**. **\[Decided in principle; implementation deferred\]**

### 4.5 Eligibility

- A player may roll only on items **sensible for their character** (usable by the class and an upgrade for them), and may roll on **every** such item. **\[Decided\]**
- Players cannot roll on items their character cannot use. **\[Decided\]**
- Eligibility is derived from item and spec data, not officer judgement, so there are no "sensible gear" arguments. **\[Proposed\]**
- How "upgrade" is determined is **parked** until that part of the addon is built. **\[Open: parked\]**

### 4.6 Main-spec and off-spec

- The role a player rolls as is **whatever they are actually doing in the raid**: tanking means rolling as a tank, DPS means rolling as DPS. Still allowing rolls for off role gear but with the off-spec penalty. **\[Decided\]** 
- Pity is per item, so switching roles between raids does not change a player's pity; only the -20 offset applies when the item is not for the current role. **\[Decided\]**
- To stop spec-swapping to dodge the penalty, snapshot the role at raid start or at each pull, with an officer override for genuine mid-raid swaps. **\[Proposed\]**
- How the role is detected (assigned roles, talent inspection, or player declaration, which is easy to lie about) is **\[Open\]**, particularly in Classic.

### 4.7 New players

- A new player starts at **0 pity on every item**. **\[Decided\]**
- They are expected to be mostly locked out of heavily contested items but always keep a nonzero chance (see 7.3).
- Their position improves over time as pity accrues, and veterans win and lock themselves out of each item, and at the start of a new tier, when everyone is at 0.

### 4.8 BoE items

- First a **need roll** for players who need the item for gear. **\[Decided\]**
- If nobody needs it, a **greed roll**. **\[Decided\]**
- Pity rises for greed rollers **only if the greed roll actually happens**. **\[Decided\]**
- greed-roll pity is held in a **separate counter** and can never be used as need-roll pity. **\[Decided: accepted as sensible\]**

### 4.9 Decay and leaving

- **Leavers**: a player who leaves the guild loses **10 pity per week until 0**, so they can rejoin but at a cost. Applies to every item. The -10 decay happens every 7 days after leaveing, not on the day of leaving **\[Decided\]**
- **Absent members** (still in the guild): **\[Open\]**. Options:
  - A: never decay.
  - B: lose 10 pity per month without raid attendance, where **attempted attendance counts as present** if the raid was full and the player was benched.
  - Proposed refinements to B: a grace window (the first 2-3 missed raids do not count) and exempt excused absences. At 10 per month, a returning +50 player takes five months to reach zero.

### 4.10 New tiers and horizontal gear

- New-tier items start at 0 for everyone (a consequence of per-item pity); old-tier pity stays but is moot.
- Gear is expected to become more horizontal, so more players will want each piece and pools will be larger, which makes the new-player odds in 7.3 worse. The owner considers this covered by class-eligibility plus once-per-item. How this plays out needs more thought. **\[Open\]**

## 5. Roll flow and UI

### 5.1 Flow

1. An item drops. The writer officer opens a roll window, announced in raid chat so players without the addon see it. Windows run **one item at a time**, because a plain `/roll` cannot say which item it is for.
2. Eligible players (class-eligible, not previously winners of the item) roll with `/roll` (1-100).
3. Only the **first roll per player per window** counts; extra rolls are flagged. Rolls outside the window are ignored; rolls with a range other than 1-100 are rejected. **\[Proposed\]**
4. The writer closes the window in raid chat and publishes the list of accepted rolls. Clients check each against the rolls they observed themselves.
5. The writer computes effective rolls and resolves any ties by rerolling among the tied players.
6. The winner is announced with the full breakdown, and an officer distributes the item via master loot.
7. Once the item is awarded, every player who rolled, other than the winner, gains +10 pity on the item (to a maximum of +50).
8. The result is appended to the audit log and the updated pity table is published with a revision number and hash (6.3).

### 5.2 UI requirements

- **Pre-roll odds per person** are shown before the roll. **\[Decided\]** They only need to be **approximate**; the actual outcome is what matters. The pool is assumed to be the players who already have pity on the item. Odds use the same tie-reroll mechanism as the real roll (see Appendix A) and include the off-spec modifier. **\[Decided\]**
- The odds **update live**: when a roll is seen from a player not already in the assumed pool, they are added. Odds use only **who is in the pool and their effective pity**, never the values already rolled. This is safe because rolling can only ever help a player, whatever the other rolls are. **\[Decided\]**
- The odds are **broadcast by the writer officer**, so everyone sees identical numbers; clients recompute locally and flag any mismatch. **\[Proposed\]**
- Roll results show a breakdown, for example: `Lary: roll 62, pity +50, off-spec -20 → 92`. **\[Proposed\]**
- The pity table is visible to everyone with the addon. **\[Decided\]**
- Hiding rolls from other players is **not needed**: rolling is free and a roll cannot be changed after it is seen. **\[Decided\]**

## 6. Authority, trust and data sync

### 6.1 Central state

- Pity state is **centralised**. Only officers' copies are authoritative; discrepancies between officers are investigated. **\[Decided\]**
- Everyone else's copy is a read-only cache for their own reference and for catching discrepancies. **\[Decided\]**
- The **audit log is the source of truth**; the pity table is derived from it by replaying the log. **\[Decided\]**
- Outcomes are derived from the **recorded `/roll` chat results**, never from addon-side random numbers. `/roll` results are server-generated system messages that players cannot forge, and the raid sees them, so every client with the addon can independently verify each logged result. **\[Decided\]**
- Rule changes that alter pity outside a roll (leaver decay, absence decay, officer corrections) are recorded as dated log entries, so replaying the log always reproduces the same table. **\[Decided\]**

### 6.2 Single writer

- One officer is the **writer** for each raid session; other officers hold read-only mirrors and reconcile after the raid. This avoids two officers writing conflicting results. **\[Proposed\]**
- If the writer leaves or disconnects, **another officer takes over** as writer. **\[Decided\]**

### 6.3 Publishing the pity table

- The pity table is **published to everyone with the addon**. **\[Decided\]**
- **Only officers can push updates**, and clients accept updates **only from officers**. **\[Decided\]**
- The game stamps the real sender name on addon messages, so "is the sender an officer" can be checked against guild rank. **\[Proposed as mechanism\]**
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

The 12% in the design tenets holds only against **one** capped player. This is the worst case; it eases as winners remove themselves from the pool and resets at tier launch. However it is the main decider for whether the cap should drop to +40 or not.

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
| Alts and extra characters | Pity is per character, so playing one character means not playing another; alts accrue pity slower. Confirm per-character tracking. |
| Win then give the item to a friend | Allowed. The winner is locked out of that item permanently. |
| BoE and vendor items | Raid drops are BoP. BoE: need roll first, then greed roll with a separate pity counter. |
| Seeing rolls before committing | Irrelevant: rolling is free and rolls cannot be changed. |
| Tampering with pity state | Centralised officer-held state; clients accept only officer updates; hashes and audit log (6). |
| Spec-swapping to dodge the off-spec penalty | Snapshot role at raid start or per pull. **\[Proposed\]** |
| Spamming rolls or odd roll ranges | First roll per window only; reject non-1-100 ranges. **\[Proposed\]** |
| Returning with stale high pity | Decay options in 4.9. **\[Open\]** |
| Passing an item to dodge the lockout (duplicates) | Pity reset plus first copy must be equipped. **\[Deferred\]** |

## 9. Accepted shortcomings (explicitly decided)

- **Pity saturates after 5 losses.** If 8 people have all waited around two months for an item, everyone ends up at +50 and someone has to win; it becomes a lottery among long-waiters. **\[Decided\]**
- **New players are mostly locked out** of contested items (7.3), but never completely. **\[Decided\]**
- **Need-blind**: no weighting by how big the upgrade is. **\[Decided\]**
- **No cross-item fairness**: a player can win several items in a run. To reach five items at +50 they must have lost every one of them repeatedly. **\[Decided\]**
- **Pity is not a guarantee**: a +50 player still loses about 12% of the time to a fresh player, and half the time to another +50 player.
- **Off-spec pity accrues at the full rate**, so a long-waiting off-spec player (+50 less 20 = +30) beats a fresh main-spec player about 76% of the time. **\[Decided\]**
- **Diminishing returns** from the clamp at 100: the first +10 adds about 10 points of win chance, the last about 6.

## 10. Open questions

1. Whether passing leaves pity unchanged or resets it.
2. Absence decay: none, or -10 per month, with grace window, excused absences, and how "attempted attendance" is defined.
3. Off-spec penalty size (-20 versus -10) and whether to floor.
4. Role detection method in WoW: Forever and when the role is snapshotted.
5. Whether to keep the +50 cap or lower it (7.4).
6. Which guild ranks count as "officer" for publishing and accepting table updates.
7. Duplicate-equippable item handling: build only if it actually comes up (`C_Item.GetItemUniqueness` can detect candidates).
8. How "upgrade" in the eligibility rule (4.5) is determined from item data. Parked until needed.
9. Runtime behaviour to confirm in the beta client: roll system messages arrive and parse as expected, raid roles and inspected specs are readable (not secret) out of combat, and addon messages are not restricted.
10. Addon message limits. Messages go through AceComm and ChatThrottleLib, which pace them by bandwidth and retry any the client reports as throttled; live roll messages go out before ledger sync. The harness assumes the client allows 10 messages at once per prefix, then 1 a second. If that's right, live rolls fit (they're batched), but a first full ledger sync is slow (roughly 250 bytes a second per officer, after compression). Measure in the beta.
11. Officer ranks are a local setting (`/pl officerrank`, default ranks 0-1). Clients with different settings disagree about whose updates count. Consider storing it in the ledger.
12. `C_Item.GetItemSpecInfo` may list tank specs on DPS items (it follows primary stats), so the automatic off-spec flag can miss role mismatches. The writer can flip any entrant's flag before the first round closes.
13. Leaving and rejoining the guild are recorded by hand (`/pl leave`, `/pl rejoin`). Automatic detection from the guild roster would need one officer to own it, or every officer would record the same leave.
14. If the writer reloads mid-roll, their copy of the roll is gone and only the writer answers requests for it, so another officer has to take over from their own copy. Tied players who do not reroll are dropped from the reroll.

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

Forever has Retail-style specialisations, so main-spec and off-spec can likely be decided per item with `C_Item.GetItemSpecInfo` against the player's current spec. This bears on open question 4.

## Revision history

- **v0.1 (7 Oct 2026)**: initial draft consolidating the design discussion.
- **v0.2 (7 Oct 2026)**: client (WoW: Forever), master loot, out-of-combat only, GUID keying; pity award timing; modifier before clamp confirmed; approximate odds; audit log as source of truth; writer handover; sequential roll windows; new open questions 8-10.
- **v0.3 (7 Oct 2026)**: live-updating odds from pool and pity only; multiple copies (top N); upgrade rule parked; duplicates left until needed; Appendix B (Forever API notes).
