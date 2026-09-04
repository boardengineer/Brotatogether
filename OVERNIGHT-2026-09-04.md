# Overnight work — 2026-09-04

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

**Robust fallback if needed (NOT implemented):** send post-harvest per-player gold + `bonus_gold`
as a **reliable** one-shot wave-end event (new key on the existing MAIN_STATE_EVENTS channel), so it
can't be lost. More code (serialize + client apply), but loss-proof. Only do this if the two-machine
test shows the unreliable snapshot fix is insufficient.

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

---

## Next steps when you're back
- Two-machine validate the gold candidate fix (section 1) before shipping.
- Decide on the deferred items above.
