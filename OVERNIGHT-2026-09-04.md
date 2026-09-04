# Overnight work — 2026-09-04

## ✅ VALIDATED 2026-09-04 (two-machine test)
The gold + xp/level fix (commits `4cdc8e9` + `356d39a`) **passed** a two-machine test. A genuinely
divergent case: host authoritative per-player values were p0 `gold=64 xp=34 level=0` / p1 `gold=53
xp=7 level=1` at shop 1, and p0 `gold=108 xp=41 level=1` at shop 2. The **client applied the exact
same values** (a temp `BTGOLDSHOP` trace, since removed, confirmed host-send == client-apply per
player), and the client's vanilla `log.txt` showed post-harvest totals (P0 64 / P1 53) carried into
wave 2 — i.e. the old stale-30/30 symptom is gone. No SCRIPT ERROR from the extra wave-end send or
the shop xp/level apply. The `[UNVALIDATED]` tags on those two commits can now be considered cleared.
(Minor: a cosmetic 1-line baseline drift in each machine's pre-existing `coop_shop.gd` — a commented
`print_debug` — will reconcile when the branch is pushed and B pulls the repo copy.)

---

## TL;DR — morning checklist
- **Gold divergence: root-caused.** The client skips base `manage_harvesting()`, so wave-end harvest
  gold/xp are host-only. Gold self-heals via the shop; **xp/level did not** — that's the worse half.
- **Candidate fixes on this branch (all `[UNVALIDATED]`):** (1) host pushes an authoritative snapshot
  right after harvest [`4cdc8e9`], (2) xp/level added to the reliable shop packet [`356d39a`].
- **Safe, ship-ready fix:** lobby-chat "host left" guard [`336e4cd`] (defensive, no wire change).
- **Bonus:** a full host/client divergence audit (§4) turned up F1–F6; F1/F2 (xp/level) are addressed,
  F3 (`on_wave_end`/`LinkedStats` skip) documented for you to decide.
- **To validate the gold/xp fixes:** both machines on the SAME manifest version (compat gate!), set
  `ENABLE_DEBUG = true` in `extensions/main.gd` on both, run a wave, compare the `BTGOLD host` vs
  `BTGOLD client` lines. Details in §1.
- Nothing on `main`, nothing pushed. Cherry-pick/merge what you want.

---

Branch: `overnight-2026-09-04` (off `main` @ 3220f02, 1.4.1). Nothing committed to `main`, nothing pushed.
All changes below are on this branch and mirrored source⇄install; each is parse-checked solo
(boots clean, only the benign `pd_turret` reload noise). Netcode-affecting changes are marked
**UNVALIDATED (needs two-machine test)** — do not ship those without running them on both machines.

---

## 1. Gold divergence — DIAGNOSED + candidate fix (UNVALIDATED)

**Symptom:** at end of a wave the host shows unequal per-player gold (e.g. P0=38 P1=59) while the
client shows the near-equal mid-wave values (30/30).

**Root cause (traced through both codebases):**
- Vanilla gold is per-player in `RunData.players_data[i].gold`, mutated only via `add_gold`. During
  a wave, gold pickups are split round-robin between players (`main.gd:879`), which keeps the two
  players near-equal (the client's 30/30).
- At **wave end**, base `_on_WaveTimer_timeout` → `manage_harvesting()` (`main.gd:1300`) adds
  **per-player, UNEQUAL** harvest gold via `RunData.add_gold(val, player_index)` where `val` is that
  player's harvesting stat + bonuses — and `clean_up_room()` folds leftover materials into
  `bonus_gold`. This is what makes the host end unequal (38/59).
- The mod's client `_on_WaveTimer_timeout` (`extensions/main.gd:~901`) **deliberately skips** the
  base logic — it only dims the screen and freezes players. So the client never computes harvest
  gold. The client is host-authoritative: it *overwrites* gold from the host's snapshot
  (`unit.gd:107`, assignment not addition) and from the shop's gold sync (`coop_shop.gd:373`).
- Gold rides the **unreliable** MAIN_STATE snapshot. Between wave-end and the shop scene loading,
  only a few snapshots go out; if the post-harvest one(s) are lost, the client keeps showing stale
  pre-harvest gold until the shop's (reliable) gold sync corrects it.

**Ruled out:** double-counting (client never awards material gold — `_spawn_item` omits the
`picked_up`→`on_gold_picked_up` connection that base `main.gd:754` makes; and it overwrites, doesn't
add); player-index/P0-P1 mismatch (both sides key by the same `player_index`; a mapping bug would
swap equal totals, not drop the sum); pickup-proximity (client never converts materials to gold).

**Candidate fix (committed on this branch, `4cdc8e9`, UNVALIDATED):** in the host branch of
`_on_WaveTimer_timeout`, after `._on_WaveTimer_timeout()` (which runs harvest), push one explicit
`_send_game_state()` so the post-harvest per-player gold + bonus_gold reach the client promptly
instead of waiting on the next scheduled tick or the shop sync. Reuses the existing snapshot→
`update_client_player` apply path (no new message type). Added an `ENABLE_DEBUG`-gated `BTGOLD`
trace on both host (post-harvest) and client (at-wave-end, with `seq`) so the divergence is
measurable.

**How to validate (two machines):** set `const ENABLE_DEBUG = true` in `extensions/main.gd` on BOTH
machines, run a normal wave, and compare the `BTGOLD host ...` line to the `BTGOLD client ...` line
at the same wave. PASS = client per-player gold matches the host's post-harvest values by the time
the wave-cleared screen shows (and certainly before the shop). If it still diverges (e.g. that one
snapshot was dropped), escalate to the robust fix below.

**Important nuance from the audit (section 4):** gold already HAS a reliable backstop — the shop's
`GOLD` sync (`coop_shop.gd:373`) — so for gold the wave-end push above just makes the correction
prompt; even if that snapshot drops, the shop fixes gold. **XP and level did NOT have any reliable
backstop** (they ride the unreliable snapshot only), which is the more severe half of this bug — so I
also added `current_xp`/`next_level_xp`/`current_level` to the reliable shop packet (`coop_shop.gd`,
commit 356d39a). Together: the wave-end push = prompt best-effort, the shop packet = guaranteed
correction. Validate both on two machines.

## 2. Safe fixes (parse-checked solo)

### 2a. Lobby-chat "host left" guard — DONE, low risk, ship-ready
`steam_connection.gd` `_on_lobby_chat_update`: the LEFT branch fired `if change_id ==
game_lobby_owner_id` with **no lobby_id filter**, so a LEFT event in the global-chat lobby (or a
lobby we bailed out of, e.g. an incompatible join) whose leaver id matched `game_lobby_owner_id`
could spuriously push "Host left the lobby" and kick us back to the menu. Guarded the side-effecting
branch with `lobby_id == game_lobby_id and game_lobby_id != -1`, matching the ENTERED branch. Pure
defensive guard (only *prevents* a wrong action; can't regress the normal host-left path). Does not
touch the wire protocol.

Note: the wave-end harvest also adds **XP** (`RunData.add_xp(val, player_index)` alongside the gold),
which rides the same player snapshot field, so the section-1 fix corrects the client's wave-end XP by
the same mechanism — worth confirming in the same two-machine test.

## 3. Deferred / documented (not changed tonight)

- **Double `_on_EndWaveTimer_timeout` guard** — cosmetic and the exact trigger is ambiguous; it
  would edit `main.gd` (netcode file) and needs two-machine validation. Left for review.

- **Absent-player chooser/GO guard (harness v11)** — *design ready, not implemented* (only matters in
  a client-drop scenario that can't be validated single-machine). Problem: when a client leaves
  mid-run, Brotato's co-op post-wave chooser / shop yields on **every** player, so the host wedges
  waiting on the departed player (this is the "game paused" you saw). Fix, harness-only
  (`bt_harness.gd`): in `_ap_postwave_tick` and `_ap_shop`, when `sc.is_host()` and
  `sc.lobby_members.size() < RunData.get_player_count()`, also drive the ABSENT players' containers:
  for each `idx` in `range(get_player_count())` not backed by a lobby member, run the same
  Take/choose logic on `ui._get_player_container(idx)` (post-wave) and `scene._on_GoButton_pressed(idx)`
  (shop). On the host those presses apply directly, same as forwarded client presses, so a departed
  client can never block the host. Validate by hosting, joining with a client, killing the client
  mid-run, and confirming the host still advances through the chooser and next wave.

## 4. Netcode divergence audit (other latent host/client drift)

A read-only audit for other bugs of the same class as the gold divergence. Key architectural fact:
the only **reliable** correction paths for run state are (1) the reliable events channel (deaths,
spawns, FX) and (2) the **shop state packet** (`coop_shop.gd`), which re-syncs `EFFECTS, ACTIVE_SETS,
LOCKED_ITEMS, WEAPONS, ITEMS, GOLD, SHOP_ITEMS, REROLL_*`. Everything else (xp, level, HP,
bonus_gold) rides ONLY the unreliable snapshot.

**F1 / F2 — HIGH — wave-end XP & level have no reliable backstop. ADDRESSED (candidate, UNVALIDATED).**
Same root as gold (client skips base wave-end), but worse: gold/effects/items are corrected by the
shop packet, while `current_xp`/`next_level_xp`/`current_level` are not — a dropped wave-end snapshot
leaves the client's xp bar / level stale through the whole shop until the next wave's first snapshot.
Fixed this branch: (a) the wave-end authoritative snapshot push (`main.gd`, commit 4cdc8e9) makes it
prompt best-effort, and (b) xp/level added to the **reliable** shop packet (`coop_shop.gd`, commit
356d39a) so it can't be lost. Needs two-machine validation.

**F2 tail — bonus_gold & player HP at wave end** — also unreliable-only, but **self-healing**:
bonus_gold is re-sent every snapshot and HP is re-sent next wave, so a single drop is transient. Left
as-is (low urgency); could fold into the same reliable summary if desired.

**F3 — MED — client never runs `RunData.on_wave_end()` / `LinkedStats.reset()`** (`main.gd:941`, no
client else-branch calling base `._on_EndWaveTimer_timeout()`). `wave_in_progress` never resets to
false on the client, and linked-stat contributions can carry across waves in the client's local stat
cache until the shop `EFFECTS` sync overwrites them. Correctness cleanup; minor observable impact
today because HP/stats are snapshot/shop driven. **Not changed** — wants a small client-side
`on_wave_end()`/`LinkedStats.reset()` call, needs validation.

**F4 — LOW — challenge/account-unlock completion is host-only** (`main.gd:1223+`, `run_data.gd:870`).
Client never simulates, so coop play won't fire client-side account unlocks. Account progression, not
run state — flagged, not urgent. **Not changed.**

**F5 — CLEAN (client double-application)** — none found. Client-spawned gold/consumables don't
connect `picked_up`, client players don't self-simulate damage/kills (`unit.gd:33-42`,
`_current_cooldown=9999`), and xp is written from the snapshot rather than via `add_xp`, so level-ups
never double-fire. One LOW cosmetic caveat: client consumables aren't collision-disabled outside
`is_solo_test`, so a client could self-hide a consumable the host still shows (re-synced next
snapshot).

**F6 — LOW — player-index mapping is consistent.** Host builds `PLAYERS` in `_players` order, client
applies by the same index everywhere. The one assumption to keep in mind: weapons are applied
positionally by `weapon_index` into `current_weapons`, so they rely on the shop `WEAPONS` sync keeping
weapon ordering identical. No index-swap divergence found.

**Recommended fix order:** F1/F2 xp/level (done, validate) → F2 bonus_gold/HP (optional) → F3
on_wave_end/LinkedStats → F4/F5/F6 (low).

---

## Next steps when you're back
- **Before any two-machine test:** both machines must be on the SAME manifest version, or the new
  compat gate (1.4.x) will (correctly) block the join. This branch's `main.gd`/`steam_connection.gd`
  changes don't bump the version, so both machines just need to mirror this branch's files. Note the
  earlier note that B's manifest was left at 1.4.0 vs A's committed 1.4.1 — align them first.
- Two-machine validate the gold candidate fix (section 1) with `ENABLE_DEBUG = true` on both, before
  shipping. Also confirm wave-end XP converges (same fix path).
- Review section 4 (divergence audit) and decide which to fix next.
- Decide on the deferred items (section 3).
- This is all on branch `overnight-2026-09-04` (off 1.4.1 @ 3220f02). Cherry-pick / merge what you
  want; the gold fix commit is tagged `[UNVALIDATED]` on purpose.
