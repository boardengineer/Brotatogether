extends Node
# Brotatogether automated-test harness. Startup args drive lobby host/join (and,
# with --bt-autoplay, the whole selection flow into a wave) so two machines can run
# connection/gameplay tests without a human operating the UI. Godot 3 exposes user
# args after "--", read via OS.get_cmdline_args().
#
#   --bt-host              create a public game lobby and wait for a client
#   --bt-join              refresh the worldwide lobby list, join the first game lobby
#   --bt-join=<host_name>  join only the lobby whose lobby_name matches <host_name>
#   --bt-autoplay          after connecting, auto-select character/weapon and (host)
#                          advance each stage and pick difficulty, starting a wave
#
# Local player index is 0 on the host, 1 on the client (lobby order, matching the
# device placement seen in the connection test). The host's _on_selections_completed
# advances character->weapon->difficulty; the host's difficulty_pressed starts the run.

const MP_MENU_SCENE = "res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_menu.tscn"
const STABILIZE_FRAMES = 120   # ~2s at 60fps: let a screen's focus/lobby sync settle

var _mode := ""
var _key_test := false     # --bt-key-test: press 0 then 9 in each co-op shop and log carousel pages
var _key_test_scene := 0
var _key_test_frames := 0
var _key_test_done := {}
var _key_before := []
var _key_after_0 := []
var _key_state := 0
var _key_press_frame := 0
var _pop_before := false
var _pop_after_0 := false
var _pop_after_refocus := false
var _mouse_test := false     # --bt-mouse-test: click / hover own and other panels in each co-op shop
var _mouse_scene := 0
var _mouse_frames := 0
var _mouse_done := {}
var _mouse_log := {}
var _icon_test := false      # --bt-icon-test: count empty key-hint icons per co-op shop / level-up
var _icon_done := {}
var _armed := false        # any --bt-* flag present; otherwise the harness is fully inert
var _rc_lock := []          # --bt-lock=2,3: host locks these slots once the lobby exists
var _rc_lock_done := false
var _rc_kick_slot := -1     # --bt-kick=<slot>:<secs>: host kicks that slot <secs> after it is seated
var _rc_kick_delay := 0.0
var _rc_kick_since := -1.0
var _rc_kick_done := false
var _join_name := ""
# --bt-solo: take the multiplayer menu's "solo test" path without a click (a fake lobby of
# one, is_solo_test on). in_multiplayer_game is true and the co-op shop runs, so every
# HOST-side path can be exercised on one machine with no second player.
var _solo := false
# --bt-fake-peer: with --bt-solo, seat a second, non-existent member so player_count is 2.
# Everything that only runs at two players then executes -- the other panel's gear container,
# the synced-stat loop, _focus_dictionary_for_player(1) -- and send_shop_state builds a real
# two-player packet, whose compressed size is recorded before any send is attempted.
var _fake_peer := false
const FAKE_PEER_ID := 1
# --bt-combine=<tier>[,alias][,curse][,hidden]: fabricate a combinable pair in the co-op
# shop and press Combine in-process. See _combine_tick.
var _combine_spec := ""
var _combine_scene := 0
var _combine_frames := 0
var _combine_done := {}
# --bt-curse-gift: HOST only. At every co-op shop, give each OTHER player one cursed common
# weapon (while they have a free slot) and one cursed common item, cursed through the DLC's
# own curse_item so the stats really change, then resend the shop state. Supplies the
# client-side curse display check without waiting on shop luck.
var _curse_gift := false
var _curse_gift_done := {}
# --bt-gift=<my_id>[,<my_id>...]: HOST only. Same timing as --bt-curse-gift, but gives exactly
# these items/weapons (repeat an id for a pair, e.g. weapon_knife_1,weapon_knife_1 to combine).
# --bt-gold=<n>: HOST only. Tops each OTHER player's gold up to n at every co-op shop.
var _gift_ids := []
var _gift_gold := 0
# --bt-wait-peers=<n>: HOST autoplay leaves CharacterSelection alone until the lobby holds
# n members, so a human joining a bot host is not left behind by an instant solo start.
var _wait_peers := 0
var _autoplay := false
var _acted := false
var _joined := false
var _local_idx := 0
var _ap_scene_id := 0
var _ap_frames := 0
var _ap_done := {}
var _traced := false
const CHOOSER_COOLDOWN_FRAMES = 30   # ~0.5s between post-wave presses: never spam the sync
var _chooser_cooldown := 0
const HB_INTERVAL_MS = 5000
var _hb_last_ms := 0
var _last_scene_name := ""
var _chooser_idle_frames := 0
# --bt-chat-test state: prove the global chat lobby joins + messages round-trip (self-echo and,
# across two machines, cross-client). _chat_tag labels this instance's pings (--bt-chat-tag=X).
var _chat_connected := false
var _chat_wait_frames := 0
var _chat_sends := 0
var _chat_last_send_frame := -600
var _chat_tag := "A"
var _friends_only := false   # --bt-friends-only: host creates a friends-only game lobby
var _force_stranger := false # --bt-force-stranger: host treats every joiner as a non-friend (refusal test)
# --bt-hitch=<ms>:<period_s>  (client side, paired with --bt-latprof): every <period_s>
# seconds during a wave, block the main thread for <ms> to simulate the known scene-load
# stalls. Queued MAIN_STATE snapshots then drain in one read pass on recovery, which BTLAT
# logs as a "backlog" event -- so the L2 (hitch amplification) latency is measured
# deterministically instead of waiting for a natural stall.
var _hitch_ms := 0
var _hitch_period_ms := 0
var _hitch_last_ms := 0
# --bt-danger=<N>: host presses difficulty element N (0-5) instead of the focused one.
# Higher danger reaches high enemy density waves earlier -- used by the late-wave
# latency soak. -1 = no override (press the default-focused element). NB in co-op a
# danger above the CLIENT's unlock silently no-ops -- and a wedged attempt SAVES the
# selection, poisoning the default focus for the next run -- so the wedge guard below
# retries with element 0 (always pressable) whenever the run fails to start.
var _danger := -1
var _ap_diff_wait := 0   # frames since the last difficulty press (wedge guard)
var _bots := false       # --bt-bots: AutoBattler drives this machine's local slot
var _char_id := ""       # --bt-char=<my_id>: force this slot's character (e.g. character_pacifist)
var _dil_prev_wt := -1.0  # hb dil= field state (see _hb_tick)
var _dil_prev_ms := 0
var _dil_wave := -1
# --bt-die-at=<wave>:<idx>[,<wave>:<idx>...] (HOST only): 5 s into wave <wave>, kill player
# <idx> outright (Player.die() -- the host-authoritative death path, exactly what a lethal
# hit triggers). Exercises BATCHED_PLAYER_DEATHS (one dead, others alive) and, once every
# player is dead, the host's clean_up_room -> send_run_ended -> end-run screen on both
# machines. e.g. --bt-die-at=2:0,3:0,3:1 : host dies wave 2; run ends wave 3.
var _die_at := {}        # wave -> [player idx, ...]
var _pl_dead := {}       # player index -> dead at the last heartbeat (DIED/REVIVED lines)
var _mortal := false     # --bt-mortal: players can actually die (no DebugService.invulnerable)
# --bt-pd-test (both machines): scripted Primal Dread actions for the client seat, the test
# plan rows no bot reaches. Host, each shop: tops the client up (gold, meca parts), turns one
# shop offer meca, and on the first shop duplicates its first weapon so a combine exists.
# Client, each shop: buys the meca offer with effect 1, dismantles another offer, meca-upgrades
# an owned weapon, then presses GO itself (its AutoBattler slot fights but does not shop).
# Client, first chooser each wave: combines a pair, or recycles its last weapon. Both print
# BTPD state lines at shop start and after the actions: compare A and B per wave/tag.
var _pd_test := false
var _pd_shop := {}        # shop scene instance id -> next step index
var _pd_shop_t0 := {}     # shop scene instance id -> ms when first seen
var _pd_chooser_wave := -1


func _ready() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("--bt-"):
			_armed = true
		if a == "--bt-host":
			_mode = "host"
		elif a == "--bt-join":
			_mode = "join"
		elif a.begins_with("--bt-join="):
			_mode = "join"
			_join_name = a.substr(10)
		elif a == "--bt-solo":
			_mode = "solo"
			_solo = true
		elif a.begins_with("--bt-wait-peers="):
			_wait_peers = int(a.substr(len("--bt-wait-peers=")))
		elif a == "--bt-curse-gift":
			_curse_gift = true
		elif a.begins_with("--bt-gift="):
			for id in a.substr(len("--bt-gift=")).split(","):
				if id != "":
					_gift_ids.push_back(id)
		elif a.begins_with("--bt-gold="):
			_gift_gold = int(a.substr(len("--bt-gold=")))
		elif a == "--bt-fake-peer":
			_fake_peer = true
		elif a.begins_with("--bt-combine="):
			_combine_spec = a.substr(len("--bt-combine="))
		elif a == "--bt-autoplay":
			_autoplay = true
		elif a == "--bt-chat-test":
			_mode = "chat"
		elif a.begins_with("--bt-chat-tag="):
			_chat_tag = a.substr(14)
		elif a == "--bt-friends-only":
			_friends_only = true
		elif a == "--bt-force-stranger":
			_force_stranger = true
		elif a == "--bt-key-test":
			_key_test = true
		elif a == "--bt-mouse-test":
			_mouse_test = true
		elif a == "--bt-icon-test":
			_icon_test = true
		elif a.begins_with("--bt-lock="):
			for part in a.substr(10).split(","):
				if part != "":
					_rc_lock.push_back(int(part))
		elif a.begins_with("--bt-kick="):
			var kv = a.substr(10).split(":")
			_rc_kick_slot = int(kv[0])
			_rc_kick_delay = float(kv[1]) if kv.size() > 1 else 10.0
		elif a.begins_with("--bt-hitch="):
			var spec = a.substr(11).split(":")
			_hitch_ms = int(spec[0])
			_hitch_period_ms = int(float(spec[1]) * 1000.0) if spec.size() > 1 else 5000
			print("BTHARNESS hitch injector armed: %dms every %dms (waves only)" % [_hitch_ms, _hitch_period_ms])
		elif a == "--bt-bots":
			# AutoBattler integration: this machine's LOCAL player slot is driven by the
			# Pasha-AutoBattler bot (movement + autoshop + level-ups) via the per-slot
			# CoopService.is_bot_by_index flag -- NOT the global enable, which would also
			# bot the remote players' local mirrors and fight the netcode. Requires the
			# AutoBattler mod installed alongside Brotatogether on this machine. Character
			# and weapon picks go random (randomize() seeded).
			_bots = true
			randomize()
			print("BTHARNESS bots armed: local slot will be AutoBattler-driven")
		elif a.begins_with("--bt-char="):
			_char_id = a.substr(10)
			print("BTHARNESS forced character: %s" % _char_id)
		elif a == "--bt-mortal":
			_mortal = true   # skip the soak invulnerability: real deaths/revives
		elif a == "--bt-pd-test":
			_pd_test = true
		elif a.begins_with("--bt-die-at="):
			for spec in a.substr(12).split(","):
				var wi = spec.split(":")
				if wi.size() == 2:
					var w = int(wi[0])
					if not _die_at.has(w):
						_die_at[w] = []
					_die_at[w].push_back(int(wi[1]))
			print("BTHARNESS die-at armed: %s" % str(_die_at))
		elif a.begins_with("--bt-danger="):
			_danger = int(a.substr(12))
			print("BTHARNESS danger override: element %d" % _danger)
		elif a.begins_with("--bt-zone="):
			# HOST: the zone the run starts in (0 crash, 1 abyss, 2 jungle). Character
			# selection reads it from the settings in its _ready; the client gets it from
			# the host's difficulty packet, so the client needs no flag.
			ProgressData.settings.zone_selected = int(a.substr(10))
			ProgressData.settings.zone_is_random = false
			print("BTHARNESS zone override: %d" % ProgressData.settings.zone_selected)
		elif a.begins_with("--bt-start-wave="):
			# BOTH machines: RunData.reset copies DebugService.starting_wave into current_wave,
			# so a test can start at a hole wave (jungle 4/10/16) or a boss (10/20).
			DebugService.starting_wave = int(a.substr(16))
			print("BTHARNESS start wave override: %d" % DebugService.starting_wave)
		elif a.begins_with("--bt-boss="):
			# HOST: the last wave's boss (e.g. boss_brachiosaurus), via the debug hook.
			DebugService.spawn_specific_boss = a.substr(10)
			print("BTHARNESS boss override: %s" % DebugService.spawn_specific_boss)
	if _mode == "":
		set_process(false)
		return
	# Solo test is a lobby of one, so this process is slot 0 just like a host.
	_local_idx = 0 if (_mode == "host" or _mode == "solo") else 1
	if _combine_spec != "":
		_bt_trace_reset()
		_bt_trace("BTCOMBINE armed spec=%s fake_peer=%s binary_is_debug=%s" % [
			_combine_spec, str(_fake_peer), str(OS.is_debug_build())])
	if _autoplay and not _mortal:
		# Soak runs are unattended: nobody dodges, so players die by wave 1-3 and the host's
		# run-lost path tears the lobby down (leave_game_lobby). Make players invulnerable
		# (DebugService -> RunData.reset copies it -> player disables its hurtbox). Only set
		# when the harness is armed with --bt-autoplay; --bt-mortal opts back into real
		# deaths (bot runs where the AI actually dodges, death/revive propagation tests).
		DebugService.invulnerable = true
		print("BTHARNESS autoplay: DebugService.invulnerable = true (soak survivability)")
	if not _armed:
		return   # no --bt-* flag: stay silent and idle (release builds ship this file)
	print("BTHARNESS armed mode=%s join_name=%s autoplay=%s local_idx=%d" % [_mode, _join_name, str(_autoplay), _local_idx])
	# Keep ticking while the tree is paused so the heartbeat can report a pause/freeze.
	pause_mode = Node.PAUSE_MODE_PROCESS


func _process(_delta: float) -> void:
	if not _armed:
		return
	_hb_tick()
	_hitch_tick()
	var sc = get_node_or_null("/root/SteamConnection")
	if _autoplay and not _mortal and sc != null and sc.is_host():
		_invuln_tick()
	if sc != null and _mode == "host":
		_rc_tick(sc, _delta)
	if _key_test:
		_key_test_tick()
	if _mouse_test:
		_mouse_test_tick()
	if _icon_test:
		_icon_test_tick()
	if _combine_spec != "":
		_combine_tick()
	if sc == null or not Steam.loggedOn():
		return
	if not _traced:
		_traced = true
		_connect_traces(sc)
	if not _acted:
		var scene = get_tree().current_scene
		if scene != null and scene.name == "TitleScreen":
			_acted = true
			call_deferred("_drive", sc)
		return
	if _mode == "chat":
		_chat_tick(sc)
		return
	if _autoplay:
		_autoplay_tick(sc)


# DebugService.invulnerable only disables the player hurtbox, so damage that never
# touches it (acid and other puddles, burning, explosions, lose-HP effects) still landed
# on soak runs. Top every live player back up on the host each frame. A single hit
# bigger than full HP still kills, which no soak wave deals.
func _invuln_tick() -> void:
	var scene = get_tree().current_scene
	if scene == null or not ("_players" in scene):
		return
	for player in scene._players:
		if is_instance_valid(player) and not player.dead and player.current_stats.health < player.max_stats.health:
			player.current_stats.health = player.max_stats.health
			player.emit_signal("health_updated", player, player.current_stats.health, player.max_stats.health)


# --- --bt-pd-test (see the var block) -------------------------------------------------
# No global class names in here (ShopItem, Category, EffectOption, DLC2Data): this script is
# preloaded at mod init, and naming them made retail 1.2 load those classes before the
# script extensions were installed -- 209 parse errors and no game (1.6.9 boot, A).
func _pd_weapons_str(p: int) -> String:
	var out = []
	for w in RunData.get_player_weapons(p):
		out.push_back("%s%s" % [w.my_id, "[M]" if w.is_meca else ""])
	return ",".join(out)


func _pd_state(tag: String) -> void:
	for p in RunData.get_player_count():
		var meca_items = 0
		for it in RunData.get_player_items(p):
			if it.is_meca:
				meca_items += 1
		print("BTPD state %s wave=%d p%d gold=%d parts=%d weapons=%s items=%d meca_items=%d" % [tag,
				RunData.current_wave, p, RunData.get_player_gold(p), RunData.get_player_meca_parts(p),
				_pd_weapons_str(p), RunData.get_player_items(p).size(), meca_items])


func _pd_host_gift(scene) -> void:
	var dlc = ItemService.get_dlc_data_by_id("primal_dread")
	if dlc == null or not ("_shop_items" in scene):
		print("BTPD host: no primal_dread data or shop items, skipping")
		return
	var changed = []
	for p in RunData.get_player_count():
		if p == _local_idx:
			continue
		if RunData.get_player_gold(p) < 400:
			RunData.add_gold(400 - RunData.get_player_gold(p), p)
		if RunData.get_player_meca_parts(p) < 80:
			RunData.add_meca_parts(80 - RunData.get_player_meca_parts(p), p)
		var gave = ""
		var weapons = RunData.get_player_weapons(p)
		if RunData.current_wave <= 1 and weapons.size() > 0 and weapons.size() < 6 and weapons[0].tier < 3:
			RunData.add_weapon(weapons[0].duplicate(), p)
			gave = " dup=%s" % weapons[0].my_id
		var offers = scene._shop_items[p]
		var made = ""
		for k in offers.size():
			var it = offers[k][0]
			if it.get_category() == ItemService.items[0].get_category() and not it.is_meca and not it.is_cursed and not it.is_mutant:
				offers[k][0] = dlc.meca_item(it, p)
				made = offers[k][0].my_id
				break
		scene._get_shop_items_container(p).set_shop_items(offers)
		if scene.has_method("_get_gear_container"):
			scene._get_gear_container(p).set_weapons_data(RunData.get_player_weapons(p))
		changed.push_back(p)
		print("BTPD host: wave=%d player=%d gold=%d parts=%d meca_offer=%s%s" % [RunData.current_wave, p,
				RunData.get_player_gold(p), RunData.get_player_meca_parts(p), made, gave])
	if changed.size() > 0 and scene.has_method("send_shop_state"):
		scene.send_shop_state(changed)


func _pd_shop_items(scene, p: int) -> Array:
	var out = []
	for si in scene._get_shop_items_container(p).get_children():
		if si.has_method("set_shop_item") and si.visible and si.item_data != null:
			out.push_back(si)
	return out


# Client steps 1-4 and the host's step 5 run off the shop scene's own clock, so A and B
# print their after-state at about the same moment.
func _pd_shop_tick(sc, scene) -> void:
	var sid = scene.get_instance_id()
	var now = Time.get_ticks_msec()
	if not _pd_shop_t0.has(sid):
		_pd_shop_t0[sid] = now
		_pd_shop[sid] = 0
	var t = now - int(_pd_shop_t0[sid])
	var step = int(_pd_shop[sid])
	var p = _local_idx
	if step == 0 and t >= 2500:
		_pd_state("shop-start")
		_pd_shop[sid] = 1 if not sc.is_host() else 5
	elif step == 1 and t >= 4500:
		var meca = null
		for si in _pd_shop_items(scene, p):
			if si.item_data.is_meca:
				meca = si
				break
		if meca == null and t < 9000:
			return   # the host's meca offer may still be on its way
		if meca == null:
			print("BTPD client: wave=%d no meca offer arrived" % RunData.current_wave)
		else:
			meca.effect_choice_selected = 1
			print("BTPD client: wave=%d buy meca %s choice=1 gold_before=%d" % [RunData.current_wave, meca.item_data.my_id, RunData.get_player_gold(p)])
			scene._get_shop_items_container(p).on_shop_item_buy_button_pressed(meca)
		_pd_shop[sid] = 2
	elif step == 2 and t >= 10500:
		var target = null
		for si in _pd_shop_items(scene, p):
			if not si.item_data.is_meca:
				target = si
				break
		if target == null:
			print("BTPD client: wave=%d nothing to dismantle" % RunData.current_wave)
		else:
			print("BTPD client: wave=%d dismantle %s gold_before=%d parts_before=%d" % [RunData.current_wave, target.item_data.my_id, RunData.get_player_gold(p), RunData.get_player_meca_parts(p)])
			scene._get_shop_items_container(p).on_shop_item_dismantle_button_pressed(target)
		_pd_shop[sid] = 3
	elif step == 3 and t >= 12500:
		var dlc = ItemService.get_dlc_data_by_id("primal_dread")
		var done = false
		var weapons = RunData.get_player_weapons(p)
		for i in weapons.size():
			var w = weapons[i]
			if dlc == null or w.is_meca or not ItemService.can_weapon_be_mechanized(w):
				continue
			var cost = dlc.get_meca_upgrade_cost(w)
			if cost <= 0 or RunData.get_player_meca_parts(p) < cost:
				continue
			var preview = dlc.meca_item(w, p)
			var options = 0
			for e in preview.effects:
				if e.get_script() != null and e.get_script().resource_path.find("effect_option") >= 0:
					options += 1
			if options < 2:
				continue
			var upgraded = dlc.change_effect_option_to_modular_effect(preview, 0)
			print("BTPD client: wave=%d meca upgrade weapon %d %s cost=%d parts_before=%d" % [RunData.current_wave, i, w.my_id, cost, RunData.get_player_meca_parts(p)])
			scene._on_item_meca_upgrade_selected(w, upgraded, p)
			done = true
			break
		if not done:
			print("BTPD client: wave=%d no weapon to meca-upgrade (parts=%d)" % [RunData.current_wave, RunData.get_player_meca_parts(p)])
		_pd_shop[sid] = 4
	elif step == 4 and t >= 15500:
		_pd_state("shop-after")
		if scene.has_method("_on_GoButton_pressed"):
			scene._on_GoButton_pressed(p)
			print("BTPD client: wave=%d GO pressed" % RunData.current_wave)
		_pd_shop[sid] = 6
	elif step == 5 and t >= 15000:
		_pd_state("shop-after")   # host: about when the client prints its own
		_pd_shop[sid] = 6


func _pd_chooser_action(ui) -> void:
	var p = _local_idx
	var weapons = RunData.get_player_weapons(p)
	print("BTPD client: wave=%d chooser before weapons=%s" % [RunData.current_wave, _pd_weapons_str(p)])
	for i in weapons.size():
		for j in range(i + 1, weapons.size()):
			if weapons[i].my_id == weapons[j].my_id and weapons[i].tier < 3 and not weapons[i].is_meca and not weapons[j].is_meca:
				print("BTPD client: wave=%d chooser combine %s" % [RunData.current_wave, weapons[i].my_id])
				ui._on_weapon_combine_button_pressed(weapons[i], p)
				return
	if weapons.size() > 1:
		print("BTPD client: wave=%d chooser recycle %s" % [RunData.current_wave, weapons[weapons.size() - 1].my_id])
		ui._on_weapon_discard_button_pressed(weapons[weapons.size() - 1], p)
	else:
		print("BTPD client: wave=%d chooser: one weapon, nothing to recycle" % RunData.current_wave)


# Deterministic stall injector (see --bt-hitch above). Blocks only during a live,
# unpaused wave so the backlog is a stream of real 60Hz snapshots.
func _hitch_tick() -> void:
	if _hitch_ms <= 0 or get_tree().paused:
		return
	var scene = get_tree().current_scene
	if scene == null or scene.name != "Main":
		return
	var now = Time.get_ticks_msec()
	if _hitch_last_ms == 0:
		_hitch_last_ms = now   # first wave frame: start the period, don't stall instantly
		return
	if now - _hitch_last_ms >= _hitch_period_ms:
		_hitch_last_ms = now
		print("BTLAT hitch_injected ms=%d" % _hitch_ms)
		OS.delay_msec(_hitch_ms)


func _drive(sc) -> void:
	# Solo test goes straight to character selection -- the body of the multiplayer menu's
	# own _on_solo_test_button_pressed, which needs nothing from that scene. Keeping the
	# menu out of it avoids waiting on the global chat lobby for a run with no peers.
	if _mode == "solo":
		var opts = get_node_or_null("/root/BrotogetherOptions")
		if opts == null:
			print("BTHARNESS solo: no BrotogetherOptions, aborting")
			return
		sc.game_lobby_id = 1
		sc.game_lobby_owner_id = sc.steam_id
		sc.lobby_members = [sc.steam_id]
		sc.lobby_member_names = [Steam.getFriendPersonaName(sc.steam_id)]
		if _fake_peer:
			# A second seat nobody is sitting in. Its slot is flagged as left so the shop
			# does not block forever waiting for it to report arriving, but player_count is
			# still 2, so every per-player loop runs twice and the shop packet is the real
			# two-player shape. The id is bogus; sends to it just fail and get logged.
			sc.lobby_members.push_back(FAKE_PEER_ID)
			sc.lobby_member_names.push_back("FakePeer")
			if not sc.left_players.has(1):
				sc.left_players.push_back(1)
			_bt_trace("BTCOMBINE fake peer seated in slot 1 (flagged left so nothing waits on it)")
		opts.is_solo_test = true
		opts.joining_multiplayer_lobby = true
		print("BTHARNESS solo test: fake lobby of one, entering character selection")
		var _se = get_tree().change_scene(MenuData.character_selection_scene)
		return

	print("BTHARNESS entering multiplayer menu")
	var _e = get_tree().change_scene(MP_MENU_SCENE)
	yield(get_tree().create_timer(1.0), "timeout")
	if _mode == "chat":
		# Chat test: sit on the multiplayer menu and let SteamConnection's own 3s timer
		# find/create/join the global chat lobby. _chat_tick drives send + receive logging.
		print("BTHARNESS chat-test: parked on multiplayer menu, waiting for global_chat_lobby_id")
		return
	if _mode == "host":
		print("BTHARNESS create_new_game_lobby (friends_only=%s)" % str(_friends_only))
		sc.debug_force_stranger = _force_stranger
		sc.create_new_game_lobby(_friends_only)
	else:
		if not sc.is_connected("game_lobby_found", self, "_on_lobby_found"):
			var _c = sc.connect("game_lobby_found", self, "_on_lobby_found")
		# Retry the one-shot search until we actually join -- the host lobby may not be
		# OPEN yet at our first search, or a single search may miss the window.
		var tries = 0
		while not _joined and tries < 200:
			print("BTHARNESS request_lobby_search (try %d)" % tries)
			sc.request_lobby_search()
			tries += 1
			yield(get_tree().create_timer(3.0), "timeout")


# --bt-chat-test: once SteamConnection has found/created the global chat lobby, send one
# message and log every global_chat_received. Steam echoes lobby chat back to the sender, so
# a solo run that RECEIVES its own ping proves create/join + send + receive + signal end to end.
func _chat_tick(sc) -> void:
	if not _chat_connected:
		if not sc.is_connected("global_chat_received", self, "_on_chat_received"):
			var _c = sc.connect("global_chat_received", self, "_on_chat_received")
		_chat_connected = true
		print("BTHARNESS chat-test: connected to global_chat_received")
	_chat_wait_frames += 1
	var lid = sc.global_chat_lobby_id
	if lid == null or int(lid) <= 0:
		if _chat_wait_frames % 180 == 0:
			print("BTHARNESS chat-test: waiting for global chat lobby (frames=%d id=%s creating=%s querying=%s)" % [_chat_wait_frames, str(lid), str(sc.is_creating_global_chat_lobby), str(sc.is_querying_global_chat)])
		return
	# In a lobby. Send a tagged ping every ~10s (up to 8) so whichever moment the other client
	# converges onto this lobby, it will catch a later ping -- robust to join-order timing.
	if _chat_sends < 8 and (_chat_wait_frames - _chat_last_send_frame) >= 600:
		_chat_last_send_frame = _chat_wait_frames
		_chat_sends += 1
		var msg = "BTCHAT %s #%d %s" % [_chat_tag, _chat_sends, _wall_clock()]
		sc.send_global_chat_message(msg)
		print("BTHARNESS chat-test: lobby=%s SENT '%s'" % [str(lid), msg])


func _on_chat_received(user, message) -> void:
	print("BTHARNESS chat-test: RECEIVED from '%s': '%s'" % [str(user), str(message)])


func _on_lobby_found(lobby_id, lobby_name) -> void:
	if _joined:
		return
	print("BTHARNESS lobby_found id=%s name=%s" % [str(lobby_id), str(lobby_name)])
	if _join_name != "" and _join_name.to_lower() != str(lobby_name).to_lower():
		return
	_joined = true
	print("BTHARNESS joining id=%s name=%s compat=%s" % [str(lobby_id), str(lobby_name),
		$"/root/SteamConnection".compat_mismatch_reason(lobby_id).replace("\n", " | ")])
	Steam.joinLobby(lobby_id)


# --- Autoplay: drive each selection screen once, after it has stabilized ---------
func _autoplay_tick(sc) -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	if _wait_peers > 0 and scene.name == "CharacterSelection" and sc.is_host() and ("lobby_members" in sc) and sc.lobby_members.size() < _wait_peers:
		_ap_frames = 0
		return
	if _bots and CoopService.get("is_bot_by_index") != null and _local_idx < CoopService.is_bot_by_index.size():
		# Idempotent re-assert: mode switches call clear_coop_players() which wipes the flags.
		CoopService.is_bot_by_index[_local_idx] = true
		if _pd_test and not sc.is_host() and CoopService.get("autoshop_by_index") != null and _local_idx < CoopService.autoshop_by_index.size():
			CoopService.autoshop_by_index[_local_idx] = false   # the PD test owns this slot's shop
	# Post-wave chooser lives INSIDE Main (no scene change), so it needs a per-frame poll
	# rather than the instance-keyed once-per-scene dispatch below.
	if scene.name == "Main":
		_ap_postwave_tick(sc, scene)
		_die_tick(sc, scene)
	if _pd_test and (scene.name == "Shop" or scene.name == "CoopShop"):
		_pd_shop_tick(sc, scene)
	# Difficulty wedge guard: a press can silently no-op (co-op caps danger at the
	# CLIENT's unlock; a stale saved selection poisons the default focus too). If the
	# run hasn't started ~3s after ANY press, force element 0 (always pressable) and
	# re-drive; keeps retrying every ~3s while stuck.
	if scene.name == "DifficultySelection" and _ap_done.has(scene.get_instance_id()):
		_ap_diff_wait += 1
		if _ap_diff_wait >= 180:
			_ap_diff_wait = 0
			print("BTHARNESS autoplay difficulty: no run start 3s after press (danger=%d) -- forcing element 0" % _danger)
			_danger = 0
			_ap_done.erase(scene.get_instance_id())
			_ap_frames = 0
	# Key on the scene INSTANCE, not its name: the host's CharacterSelection reloads
	# itself when the client joins (lobby_players_updated -> reload_scene), producing a
	# fresh instance with the same name. Name-keying skipped it; instance-keying re-drives.
	var sid = scene.get_instance_id()
	if sid != _ap_scene_id:
		_ap_scene_id = sid
		_ap_frames = 0
	_ap_frames += 1
	if _ap_frames != STABILIZE_FRAMES or _ap_done.has(sid):
		return
	_ap_done[sid] = true
	var sname = scene.name
	if sname == "CharacterSelection":
		_ap_select(sc, scene, "character")
	elif sname == "WeaponSelection":
		_ap_select(sc, scene, "weapon")
	elif sname == "DifficultySelection":
		_ap_difficulty(sc, scene)
	elif sname == "Shop" or sname == "CoopShop":
		# Solo shop root is "Shop"; the co-op shop scene (what a multiplayer run actually
		# loads between waves) is rooted "CoopShop".
		_ap_shop(sc, scene)


func _ap_select(sc, scene, kind) -> void:
	var sname = scene.name
	var pc = RunData.get_player_count()
	var members = -1
	if ("lobby_members" in sc):
		members = sc.lobby_members.size()
	print("BTHARNESS autoplay %s: is_host=%s local_idx=%d player_count=%d lobby_members=%d" % [kind, str(sc.is_host()), _local_idx, pc, members])
	if scene.has_method("_set_selected_element") and _local_idx < pc:
		# Random character/weapon for bot runs: _set_selected_element takes a PLAYER
		# index (it commits that player's FOCUSED element), so randomize by focusing a
		# random inventory element first, then committing our own slot. (Passing a random
		# number as the player index was an out-of-bounds Array read -- B's catch.)
		var forced = (kind == "character" and _char_id != "")
		if (_bots or forced) and scene.has_method("_get_inventories") and scene.has_method("_on_element_focused"):
			var sel_inv = scene._get_inventories()
			if sel_inv.size() > 0 and sel_inv[0].get_child_count() > 0:
				var sel_el = sel_inv[0].get_child(randi() % sel_inv[0].get_child_count())
				if forced:
					# --bt-char: focus the inventory element whose item my_id matches, else fall
					# back to the random pick and say so.
					var hit = null
					for el in sel_inv[0].get_children():
						if ("item" in el) and el.item != null and ("my_id" in el.item) and el.item.my_id == _char_id:
							hit = el
							break
					if hit != null:
						sel_el = hit
					else:
						print("BTHARNESS forced character %s NOT FOUND in inventory (%d elements); random pick" % [_char_id, sel_inv[0].get_child_count()])
				scene._on_element_focused(sel_el, _local_idx)
				# _set_selected_element only flags the slot; the character used at run start is
				# _player_characters[idx], filled by vanilla _on_element_pressed and nothing else.
				# Without this the forced/random focus was cosmetic and the pick fell to random.
				if kind == "character" and ("_player_characters" in scene) and ("item" in sel_el):
					scene._player_characters[_local_idx] = sel_el.item
					print("BTHARNESS autoplay character: committing %s" % (sel_el.item.my_id if sel_el.item != null else "RANDOM"))
		if kind == "weapon" and _pd_test and scene.has_method("_get_required_pick_count") and scene.has_method("_get_inventories"):
			# PD test: real picks through _on_element_pressed (as a click does), as many as
			# the character needs (Survivor: 2), so row 3 checks the weapons that were PICKED.
			var need = scene._get_required_pick_count(_local_idx)
			var invs = scene._get_inventories()
			var picks = []
			if not invs.empty():
				for el in invs[min(_local_idx, invs.size() - 1)].get_children():
					if not ("item" in el) or el.item == null or el.is_random or el.is_special or el.get("is_locked") == true:
						continue
					picks.push_back(el)
					if picks.size() >= need:
						break
			if not picks.empty():
				while picks.size() < need:
					picks.push_back(picks[0])
				var ids = []
				for el in picks:
					ids.push_back(el.item.my_id)
				print("BTPD weapon picks: player=%d need=%d picks=%s" % [_local_idx, need, ",".join(ids)])
				for el in picks:
					scene._on_element_pressed(el, _local_idx)
		scene._set_selected_element(_local_idx)
		print("BTHARNESS autoplay %s: _set_selected_element(%d) called" % [kind, _local_idx])
		if (kind == "character" or kind == "weapon") and _local_idx < RunData.players_data.size():
			var cc = RunData.players_data[_local_idx].current_character
			print("BTHARNESS autoplay character committed: %s" % (cc.my_id if cc != null else "<null>"))
	if sc.is_host():
		# Do NOT advance until the client is present -- advancing calls
		# send_character_selection_completed, which sets lobby_status=CLOSED and hides
		# the lobby from the client's OPEN-only search before it can join.
		# Solo test has no client to wait for and never will -- waiting out the full 240s
		# just to advance anyway wastes four minutes per run.
		var waited = 0
		while not _solo and RunData.get_player_count() < 2 and waited < 240:
			if waited % 5 == 0:
				print("BTHARNESS host waiting for client (player_count=%d)" % RunData.get_player_count())
			yield(get_tree().create_timer(1.0), "timeout")
			waited += 1
		yield(get_tree().create_timer(2.5), "timeout")   # let the client finish selecting
		if is_instance_valid(scene) and scene == get_tree().current_scene and scene.has_method("_on_selections_completed"):
			print("BTHARNESS autoplay %s: host _on_selections_completed (player_count=%d)" % [kind, RunData.get_player_count()])
			scene._on_selections_completed()
		else:
			print("BTHARNESS autoplay %s: host skip advance (%s scene changed/freed) -- instance re-drive handles it" % [kind, sname])


func _ap_difficulty(sc, scene) -> void:
	# Only the host drives difficulty. Pressing a difficulty ELEMENT runs the vanilla
	# _on_element_pressed (which change_scene()s the host into the game) AND, via the
	# ext override, steam_connection.difficulty_pressed() (which syncs the client, whose
	# _difficulty_selected then change_scene()s it too). Calling difficulty_pressed()
	# directly only sends the sync packet and never starts the host's run.
	print("BTHARNESS autoplay difficulty: is_host=%s" % str(sc.is_host()))
	if not sc.is_host():
		return
	var element = null
	# --bt-danger picks a specific difficulty element; otherwise keep the old behavior
	# (latest focused, falling back to the first element).
	if _danger >= 0 and scene.has_method("_get_inventories"):
		var dinv = scene._get_inventories()
		if dinv.size() > 0 and dinv[0].get_child_count() > 0:
			element = dinv[0].get_child(int(min(_danger, dinv[0].get_child_count() - 1)))
	if element == null and ("_latest_focused_element" in scene) and typeof(scene._latest_focused_element) == TYPE_ARRAY and scene._latest_focused_element.size() > 0:
		element = scene._latest_focused_element[0]
	if element == null and scene.has_method("_get_inventories"):
		var inv = scene._get_inventories()
		if inv.size() > 0 and inv[0].get_child_count() > 0:
			element = inv[0].get_child(0)
	if element == null:
		print("BTHARNESS autoplay difficulty: no difficulty element found -- cannot start run")
		return
	var val = "?"
	if ("item" in element) and element.item != null:
		val = str(element.item.value)
	print("BTHARNESS autoplay difficulty: pressing difficulty element value=%s" % val)
	if scene.has_method("_on_element_focused"):
		scene._on_element_focused(element, 0)   # sets panel data + syncs focus to client
	scene._on_element_pressed(element, 0)
	print("BTHARNESS autoplay difficulty: _on_element_pressed called")


# Shop (between waves): each side presses its OWN GO once. The client's press syncs to the
# host (shop_go_button_pressed -> _client_shop_go_button_pressed); whichever press completes
# the set makes the host run leave_shop() + current_wave += 1 and both scenes change to the
# game, where main.gd's waiting_to_start_round handshake starts the next wave. Buying
# nothing is fine for a soak test. _ap_done's instance keying guarantees exactly one press
# per shop per side (a second _on_GoButton_pressed would TOGGLE the ready state back off).
func _ap_shop(sc, scene) -> void:
	var pc = RunData.get_player_count()
	print("BTHARNESS autoplay shop: wave=%d is_host=%s local_idx=%d player_count=%d" % [RunData.current_wave, str(sc.is_host()), _local_idx, pc])
	if (_curse_gift or _gift_ids.size() > 0 or _gift_gold > 0) and sc.is_host():
		_curse_gift_tick(scene)
	if _pd_test and sc.is_host():
		_pd_host_gift(scene)
	if _pd_test and not sc.is_host():
		print("BTHARNESS autoplay shop: PD test owns GO, harness skipping")
		return
	if _bots:
		# GO is a TOGGLE: with --bt-bots the AutoBattler autoshop presses GO itself at
		# the end of its buy/reroll flow, and a second press from the harness UN-readies
		# the player -- a 50/50 wedge per shop depending on ordering (seen live wave 3).
		# The autoshop owns GO on bot runs; the harness stays out of it.
		print("BTHARNESS autoplay shop: bots own GO, harness skipping")
		return
	# A combine test owns this shop: pressing GO here would leave for the next wave before
	# _combine_tick has fabricated its pair. It presses GO itself once the test is recorded.
	if _combine_spec != "" and not _combine_done.has(scene.get_instance_id()):
		print("BTHARNESS autoplay shop: combine test owns GO, harness skipping")
		return
	if _local_idx < pc and scene.has_method("_on_GoButton_pressed"):
		scene._on_GoButton_pressed(_local_idx)
		print("BTHARNESS autoplay shop: GO pressed for player %d" % _local_idx)


func _curse_gift_tick(scene) -> void:
	var sid = scene.get_instance_id()
	if _curse_gift_done.has(sid):
		return
	_curse_gift_done[sid] = true
	var dlc = ItemService.get_dlc_data_by_id("abyssal_terrors")
	var can_curse = _curse_gift and dlc != null and dlc.has_method("curse_item")
	if _curse_gift and not can_curse:
		print("BTHARNESS curse-gift: no abyssal_terrors curse_item, skipping curses")
	var weapons = []
	for w in ItemService.weapons:
		if w.tier == 0:
			weapons.push_back(w)
	var items = []
	for it in ItemService.items:
		if it.tier == 0 and it.effects.size() > 0:
			items.push_back(it)
	var changed = []
	for p in RunData.get_player_count():
		if p == _local_idx:
			continue
		var gave = []
		if can_curse and weapons.size() > 0 and RunData.get_player_weapons(p).size() < 6:
			var w = dlc.curse_item(Utils.get_rand_element(weapons), p)
			RunData.add_weapon(w, p)
			gave.push_back(w.my_id)
		if can_curse and items.size() > 0:
			var it = dlc.curse_item(Utils.get_rand_element(items), p)
			RunData.add_item(it, p)
			gave.push_back(it.my_id)
		for id in _gift_ids:
			var gw = ItemService.get_element_safe(ItemService.weapons, id)
			if gw != null:
				if RunData.get_player_weapons(p).size() < 6:
					RunData.add_weapon(gw, p)
					gave.push_back(id)
				continue
			var gi = ItemService.get_element_safe(ItemService.items, id)
			if gi != null:
				# Stop one short of a limited item's max, so the shop can still offer the last one.
				if gi.max_nb > 0 and RunData.get_nb_item(gi.my_id_hash, p, false) >= gi.max_nb - 1:
					continue
				RunData.add_item(gi.duplicate(), p)
				gave.push_back(id)
			else:
				print("BTHARNESS gift: unknown id %s" % id)
		if _gift_gold > 0 and RunData.get_player_gold(p) < _gift_gold:
			RunData.add_gold(_gift_gold - RunData.get_player_gold(p), p)
			gave.push_back("gold=%d" % _gift_gold)
		if gave.size() > 0:
			changed.push_back(p)
			if scene.has_method("_get_gear_container"):
				var gear = scene._get_gear_container(p)
				gear.set_weapons_data(RunData.get_player_weapons(p))
				gear.set_items_data(RunData.get_player_items(p))
		print("BTHARNESS curse-gift: wave=%d player=%d gave=%s" % [RunData.current_wave, p, str(gave)])
	if changed.size() > 0 and scene.has_method("send_shop_state"):
		scene.send_shop_state(changed)


# Post-wave chooser (inside Main, no scene change): after each wave the host shows
# CoopUpgradesUI when any player has a level-up or a crate to process and yields on
# "options_processed" until EVERY player has finished; with nobody pressing anything the
# host parks there forever and the client never gets HOST_ENTERED_SHOP. Each side drives
# only its own container: Take for items/crates, first option for level-ups. The mod's
# container override makes the same call act locally on the host and send the sync packet
# on the client (the client's container mirrors the host's via UPGRADE_MENU_STATUS).
# --bt-die-at (see above). Host only: a client-side die() would be a local-only
# cosmetic that the host never learns about.
func _die_tick(sc, scene) -> void:
	if _die_at.empty() or not sc.is_host() or get_tree().paused:
		return
	var wave = RunData.current_wave
	if not _die_at.has(wave) or not ("_wave_timer" in scene) or not is_instance_valid(scene._wave_timer):
		return
	var wt = scene._wave_timer
	if wt.is_stopped() or wt.wait_time - wt.time_left < 5.0:
		return
	for idx in _die_at[wave]:
		if idx < scene._players.size() and is_instance_valid(scene._players[idx]) and not scene._players[idx].dead:
			print("BTHARNESS die-at: killing player %d at wave %d (%s)" % [idx, wave, _wall_clock()])
			scene._players[idx].die(Entity.DieArgs.new())
	_die_at.erase(wave)


func _ap_postwave_tick(sc, scene) -> void:
	if _chooser_cooldown > 0:
		_chooser_cooldown -= 1
		return
	if not ("_coop_upgrades_ui" in scene):
		return
	var ui = scene._coop_upgrades_ui
	if ui == null or not ui.visible:
		return
	if _local_idx >= RunData.get_player_count():
		return
	var pc = ui._get_player_container(_local_idx)
	if pc == null or pc._checkmark_group.visible:
		return   # our choices are done; the host's yield resumes once everyone is
	if _pd_test and not sc.is_host() and _pd_chooser_wave != RunData.current_wave:
		_pd_chooser_wave = RunData.current_wave
		_pd_chooser_action(ui)
		_chooser_cooldown = CHOOSER_COOLDOWN_FRAMES
		return
	if pc._items_container.visible:
		var item_id = "?"
		if pc._item_data != null:
			item_id = str(pc._item_data.my_id)
		print("BTHARNESS postwave: take item %s (player %d, wave %d, is_host=%s)" % [item_id, _local_idx, RunData.current_wave, str(sc.is_host())])
		pc._on_TakeButton_pressed()
		_chooser_cooldown = CHOOSER_COOLDOWN_FRAMES
		_chooser_idle_frames = 0
	elif pc._upgrades_container.visible and pc._old_upgrades.size() > 0:
		var up = pc._old_upgrades[0]
		print("BTHARNESS postwave: choose upgrade %s (player %d, wave %d, is_host=%s)" % [str(up.my_id), _local_idx, RunData.current_wave, str(sc.is_host())])
		pc._on_choose_button_pressed(up)
		_chooser_cooldown = CHOOSER_COOLDOWN_FRAMES
		_chooser_idle_frames = 0
	else:
		# Chooser visible for us but nothing actionable: log what we're looking at, ~once/2s.
		_chooser_idle_frames += 1
		if _chooser_idle_frames % 120 == 1:
			print("BTHARNESS postwave: idle -- items_visible=%s upgrades_visible=%s old_upgrades=%d checkmark=%s (player %d, wave %d, is_host=%s)" % [str(pc._items_container.visible), str(pc._upgrades_container.visible), pc._old_upgrades.size(), str(pc._checkmark_group.visible), _local_idx, RunData.current_wave, str(sc.is_host())])


# --- Diagnostics: trace stage-completion signals on both sides. These fire on RECEIPT
# (the _receive_* handlers emit them), so a missing line pinpoints where a stage stalls:
# packet-not-received (no line) vs handler-no-op (line but no scene change). ------------
func _connect_traces(sc) -> void:
	var pairs = [["character_selection_complete", "_trace_csc"], ["weapon_selection_completed", "_trace_wsc"], ["difficulty_selected", "_trace_ds"]]
	for pair in pairs:
		if sc.has_signal(pair[0]) and not sc.is_connected(pair[0], self, pair[1]):
			var _e = sc.connect(pair[0], self, pair[1])
	print("BTHARNESS traces connected (local_idx=%d)" % _local_idx)


func _trace_csc(_a = null, _b = null) -> void:
	print("BTHARNESS signal character_selection_complete (local_idx=%d)" % _local_idx)


func _trace_wsc(_a = null) -> void:
	print("BTHARNESS signal weapon_selection_completed (local_idx=%d)" % _local_idx)


func _trace_ds(_a = null) -> void:
	print("BTHARNESS signal difficulty_selected (local_idx=%d)" % _local_idx)


func _wall_clock() -> String:
	var tm = OS.get_time()
	return "%02d:%02d:%02d" % [tm.hour, tm.minute, tm.second]


# Liveness: a scene-change line plus a 5s heartbeat with wall clock, scene, tree paused,
# Main's wave_time, current wave and lobby id. A heartbeat that stops = the process hung
# (log flushes per print in this editor build); one that continues = look at the state.
func _hb_tick() -> void:
	var tree = get_tree()
	var scene = tree.current_scene
	var sname = "<none>"
	if scene != null:
		sname = scene.name
	if sname != _last_scene_name:
		# Durable when a combine test is armed: scene transitions are the breadcrumb trail
		# that tells us how far a run got, and stdout loses its tail on an abrupt exit.
		if _combine_spec != "":
			_bt_trace("BTCOMBINE scene %s -> %s" % [_last_scene_name, sname])
		else:
			print("BTHARNESS scene %s -> %s (%s)" % [_last_scene_name, sname, _wall_clock()])
		_last_scene_name = sname
	var now = OS.get_ticks_msec()
	if now - _hb_last_ms < HB_INTERVAL_MS:
		return
	_hb_last_ms = now
	var wave_time = "n/a"
	if scene != null and ("_wave_timer" in scene) and is_instance_valid(scene._wave_timer):
		wave_time = "%.1f" % scene._wave_timer.time_left
	var chooser = "n/a"
	if scene != null and ("_coop_upgrades_ui" in scene) and scene._coop_upgrades_ui != null:
		chooser = str(scene._coop_upgrades_ui.visible)
	var lobby = -1
	var net = "n/a"
	var sc = get_node_or_null("/root/SteamConnection")
	if sc != null and ("game_lobby_id" in sc):
		lobby = sc.game_lobby_id
	if sc != null and ("last_packet_bytes" in sc) and ("unreliable_fallbacks" in sc):
		net = "%d/%d/s%d" % [sc.last_packet_bytes, sc.unreliable_fallbacks, sc.superseded_snapshots]
	# seq = host snapshots sent / client snapshots applied (per Main instance). On the client
	# an applied count that stops climbing mid-wave means snapshots are not arriving.
	var seq = "n/a"
	if scene != null and ("_state_seq" in scene) and ("_last_state_seq" in scene):
		seq = "%d/%d" % [scene._state_seq, scene._last_state_seq]
	# cli = client enemies alive / statics known / spawns pending. On the client a wave with a
	# growing host roster but cli enemies stuck at 0 means rows are not being decoded/spawned.
	var cli = "n/a"
	if scene != null and ("client_enemies" in scene) and ("client_enemy_statics" in scene) and ("client_pending_ids" in scene):
		cli = "%d/%d/%d" % [scene.client_enemies.size(), scene.client_enemy_statics.size(), scene.client_pending_ids.size()]
		# mN = ids stuck without spawn statics (the invisible-enemy class). Non-zero at
		# steady state means statics are being lost faster than the backstop heals them.
		if "_missing_statics" in scene:
			cli += "/m%d" % scene._missing_statics.size()
		# pjC-D = enemy-projectile container children vs tracked dict. C persistently
		# greater than D = orphaned duplicates the sweep can never free (the
		# 'projectiles stay on screen' class); they must track within a frame or two.
		if "_enemy_projectiles" in scene and "client_enemy_projectiles" in scene \
				and is_instance_valid(scene._enemy_projectiles):
			cli += "/pj%d-%d" % [scene._enemy_projectiles.get_child_count(), scene.client_enemy_projectiles.size()]
		# rowsN = enemy count in the MOST RECENTLY APPLIED snapshot -- a same-instant
		# pair with cli alive (enemies_max is a 5s window max vs a point sample, so
		# plateau churn makes it read high; rows==alive proves the gap is churn).
		if "_last_enemy_rows" in scene:
			cli += "/rows%d" % scene._last_enemy_rows
		# dN = confirmed-dead ids. If a hidden hole exists (host sending rows for ids the
		# client thinks dead), rows > alive shows up alongside a growing dN.
		if "client_dead_ids" in scene:
			cli += "/d%d" % scene.client_dead_ids.size()
		# pudH-C = puddles the host shipped in its last snapshot / puddle replicas on this
		# client (1.2). They should track each other; H>0 with C stuck at 0 = rows not drawn.
		if "client_puddles" in scene and "_puddle_ids" in scene:
			cli += "/pud%d-%d" % [scene._puddle_ids.size(), scene.client_puddles.size()]
		# holesN@x,y = hole walls on this machine and the first one's position. Host and
		# client must print the same value on a hole wave (the map roll is seeded).
		if "_gpe_container" in scene and is_instance_valid(scene._gpe_container):
			var holes = []
			for h in scene._gpe_container.get_children():
				if h is Hole:
					holes.push_back(h)
				for sub in h.get_children():
					if sub is Hole:
						holes.push_back(sub)
			if not holes.empty():
				cli += "/holes%d@%d,%d" % [holes.size(), int(holes[0].global_position.x), int(holes[0].global_position.y)]
	# pl=alive/total players (both sides). A client whose 'alive' stays above the host's
	# after a death = BATCHED_PLAYER_DEATHS not applied; run=L/W once a run end is known.
	var pl = "n/a"
	if scene != null and ("_players" in scene):
		var alive = 0
		for i in scene._players.size():
			var p = scene._players[i]
			var is_dead : bool = not is_instance_valid(p) or p.dead
			if not is_dead:
				alive += 1
			# Deaths/revives as their own line: on an unattended seat they were only visible
			# by diffing pl= across heartbeats (5 s resolution, same wave).
			if is_dead != bool(_pl_dead.get(i, false)) and (is_dead or _pl_dead.has(i)):
				print("BTHARNESS player %d %s wave=%d wave_time=%s" % [i, "DIED" if is_dead else "REVIVED", RunData.current_wave, wave_time])
			_pl_dead[i] = is_dead
		pl = "%d/%d" % [alive, scene._players.size()]
		if ("_is_run_lost" in scene) and ("_is_run_won" in scene):
			if scene._is_run_lost:
				pl += "/runL"
			elif scene._is_run_won:
				pl += "/runW"
	# hp=cur/max per player index (host-authoritative values on the client once snapshots
	# apply). A slot reading 1/N at the first hb of a wave is the 'starts at 1 HP' class.
	var hp = "n/a"
	if scene != null and ("_players" in scene):
		var hp_parts = []
		for p in scene._players:
			if is_instance_valid(p):
				# @x,y: compare the same slot on both machines -- a client slot that moves on its
				# own screen but not on the host's is shot standing still.
				hp_parts.append("%d/%d@%d,%d" % [p.current_stats.health, p.max_stats.health, p.global_position.x, p.global_position.y])
			else:
				hp_parts.append("x")
		hp = PoolStringArray(hp_parts).join(",")
	var fps = Engine.get_frames_per_second()
	# dil = game seconds elapsed / wall seconds elapsed since the previous hb of the SAME wave,
	# read off the host-driven wave timer. 1.00 = real time; 0.50 = the host runs at half speed.
	var dil = "n/a"
	var now_ms = OS.get_ticks_msec()
	if wave_time != "n/a":
		var wt = float(wave_time)
		if _dil_wave == RunData.current_wave and _dil_prev_wt > wt and now_ms > _dil_prev_ms:
			dil = "%.2f" % ((_dil_prev_wt - wt) / ((now_ms - _dil_prev_ms) / 1000.0))
		_dil_prev_wt = wt
		_dil_prev_ms = now_ms
		_dil_wave = RunData.current_wave
	# fx=local-slot HP drops seen / unit flashes applied to players (client only).
	var fx = "n/a"
	if scene != null and ("_bt_local_hits" in scene) and ("_bt_player_flashes" in scene):
		fx = "%d/%d" % [scene._bt_local_hits, scene._bt_player_flashes]
		if "_bt_player_flash_ok" in scene:
			fx += "/%d" % scene._bt_player_flash_ok
	print("BTHARNESS hb %s scene=%s paused=%s wave=%d wave_time=%s chooser=%s lobby=%d seq=%s net=%s cli=%s pl=%s hp=%s fps=%d fx=%s dil=%s" % [_wall_clock(), sname, str(tree.paused), RunData.current_wave, wave_time, chooser, lobby, seq, net, cli, pl, hp, fps, fx, dil])


# --- Release-candidate lobby automation (host) -------------------------------------------
# --bt-lock=2,3 locks those slots as soon as the lobby exists; --bt-kick=<slot>:<secs> kicks
# whoever sits in <slot> once it has been occupied for <secs>. Both fire once per launch.
func _rc_tick(sc, delta: float) -> void:
	if sc.game_lobby_id <= 0 or not sc.is_host():
		return
	if not _rc_lock_done and not _rc_lock.empty():
		_rc_lock_done = true
		for slot in _rc_lock:
			sc.set_slot_locked(slot, true)
		print("BTHARNESS rc: locked slots %s (open=%d)" % [str(_rc_lock), sc._roster_open_slot_count()])
	if _rc_kick_slot > 0 and not _rc_kick_done:
		if sc.lobby_members.size() > _rc_kick_slot:
			if _rc_kick_since < 0.0:
				_rc_kick_since = 0.0
			_rc_kick_since += delta
			if _rc_kick_since >= _rc_kick_delay:
				_rc_kick_done = true
				print("BTHARNESS rc: kicking slot %d (%s)" % [_rc_kick_slot, sc.lobby_member_names[_rc_kick_slot]])
				sc.kick_player(_rc_kick_slot)
		else:
			_rc_kick_since = -1.0


# --bt-key-test: in each co-op shop, inject real key presses (0, then 9) through
# Input.parse_input_event -- the full viewport input path, FocusEmulators included -- and log
# every player's carousel page before and after, plus how many arrows carry a key hint.
# Desktop Godot 3.5+ buffers injected events until the next frame, so reads are frames apart.
func _key_test_tick() -> void:
	var scene = get_tree().current_scene
	if scene == null or scene.name != "CoopShop":
		return
	var sid = scene.get_instance_id()
	if sid != _key_test_scene:
		_key_test_scene = sid
		_key_test_frames = 0
		_key_state = 0
		return
	if _key_test_done.has(sid):
		return
	_key_test_frames += 1
	var pages = _carousel_pages(scene)
	if _key_state == 0 and _key_test_frames == 20:
		_key_focus_shop_item(scene, 0)
	elif _key_state == 0 and _key_test_frames == 30:
		_key_before = pages
		_pop_before = _popup_visible(scene, 0)
		_key_test_diag(scene)
		print("BTKEYTEST press 0 frame=%d pages=%s popup0=%s" % [Engine.get_idle_frames(), str(pages), str(_pop_before)])
		_press_key(KEY_0)
		_key_press_frame = _key_test_frames
		_key_state = 1
	elif _key_state == 1 and (pages != _key_before or _key_test_frames - _key_press_frame >= 90):
		_key_after_0 = pages
		_pop_after_0 = _popup_visible(scene, 0)
		_key_focus_shop_item(scene, 1)   # a mirrored-style focus change while off the shop page
		_key_press_frame = _key_test_frames
		_key_state = 3
	elif _key_state == 3 and _key_test_frames - _key_press_frame >= 5:
		_pop_after_refocus = _popup_visible(scene, 0)
		_press_key(KEY_9)
		_key_press_frame = _key_test_frames
		_key_state = 2
	elif _key_state == 2 and (pages != _key_after_0 or _key_test_frames - _key_press_frame >= 90):
		_key_test_done[sid] = true
		print("BTKEYTEST wave=%d before=%s after_0=%s after_9=%s popup0: before=%s after_0=%s after_refocus=%s" % [
			RunData.current_wave, str(_key_before), str(_key_after_0), str(pages), str(_pop_before), str(_pop_after_0), str(_pop_after_refocus)])


# Focus shop item <slot> for player 0 the way mirrored remote focus does (straight onto the
# FocusEmulator), which makes the popup manager display that item's popup.
func _key_focus_shop_item(scene, slot: int) -> void:
	if not scene.has_method("_get_shop_items_container"):
		return
	var items = scene._get_shop_items_container(0)._shop_items
	if items.size() <= slot or not is_instance_valid(items[slot]):
		print("BTKEYTEST no shop item %d to focus" % slot)
		return
	Utils.get_focus_emulator(0).focused_control = items[slot]._button


func _popup_visible(scene, pi: int) -> bool:
	if not scene.has_method("_get_coop_player_container"):
		return false
	var pc = scene._get_coop_player_container(pi)
	return pc != null and is_instance_valid(pc) and pc.item_popup.visible

func _carousel_pages(scene) -> Array:
	var out = []
	if not scene.has_method("_get_coop_player_container"):
		return out
	for pi in RunData.get_player_count():
		var cont = scene._get_coop_player_container(pi)
		if cont != null and is_instance_valid(cont) and ("carousel" in cont) and is_instance_valid(cont.carousel):
			out.push_back(cont.carousel.index)
		else:
			out.push_back(-1)
	return out


func _press_key(scancode: int) -> void:
	for is_pressed in [true, false]:
		var ev = InputEventKey.new()
		ev.scancode = scancode
		ev.pressed = is_pressed
		Input.parse_input_event(ev)


# Key-test diagnostics: carousel state, and the nodes that receive _input FIRST (Godot 3
# dispatches the viewport input group in reverse tree order).
func _key_test_diag(scene) -> void:
	var keys = scene.get_node_or_null("BtCarouselKeys")
	if keys != null:
		keys.debug_log = true
		var cars = keys.carousels()
		var states = []
		for car in cars:
			states.push_back("active=%s trig=%s dis=%s/%s" % [str(car.active), str(car.are_trigger_buttons_active()), str(car.arrow_left.disabled), str(car.arrow_right.disabled)])
		print("BTKEYDIAG carousels=%d %s" % [cars.size(), str(states)])
	var group = "_vp_input" + str(get_viewport().get_instance_id())
	var nodes = get_tree().get_nodes_in_group(group)
	var first = []
	for i in range(nodes.size() - 1, max(-1, nodes.size() - 9), -1):
		first.push_back(str(nodes[i].get_path()).replace("/root/CoopShop", "~"))
	print("BTKEYDIAG input_group=%s size=%d first_in_line=%s" % [group, nodes.size(), str(first)])


func _input(event: InputEvent) -> void:
	if _key_test and event is InputEventKey and event.pressed and (event.scancode == KEY_9 or event.scancode == KEY_0):
		print("BTKEY harness saw scancode=%d" % event.scancode)


# --bt-mouse-test: in each co-op shop, send synthetic mouse events straight into the viewport
# (canvas coordinates, same _input order as real input) and log the results: my right arrow,
# the other player's right arrow (must be ignored), my left arrow, hovering my first shop item
# (my popup should show) and hovering the other player's first shop item (their popup must not
# change).
func _mouse_test_tick() -> void:
	var scene = get_tree().current_scene
	if scene == null or scene.name != "CoopShop" or RunData.get_player_count() < 2:
		return
	var sid = scene.get_instance_id()
	if sid != _mouse_scene:
		_mouse_scene = sid
		_mouse_frames = 0
		_mouse_log = {}
		return
	if _mouse_done.has(sid):
		return
	_mouse_frames += 1
	var sc = get_node_or_null("/root/SteamConnection")
	var me = sc.get_my_index() if sc != null else 0
	var other = (me + 1) % RunData.get_player_count()
	var mine = scene._get_coop_player_container(me)
	var theirs = scene._get_coop_player_container(other)
	match _mouse_frames:
		20:
			_mouse_log["handler"] = scene.has_node("BtMouseInput")
			if scene.has_node("BtMouseInput"):
				scene.get_node("BtMouseInput").debug_log = true
				var last = scene.get_child(scene.get_child_count() - 1)
				print("BTMOUSEDIAG last_child=%s vp_has_input=%s vp_size=%s canvas_xform=%s" % [last.name, str(get_viewport().has_method("input")), str(get_viewport().size), str(get_viewport().canvas_transform)])
			for pi in RunData.get_player_count():
				var c = scene._get_coop_player_container(pi)
				print("BTMOUSEDIAG p%d container=%s arrowR=%s" % [pi, str(c.get_global_rect()), str(c.carousel.arrow_right.get_global_rect())])
			_mouse_log["cursor_visible"] = Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE
			_mouse_log["pages_start"] = _carousel_pages(scene)
			_mouse_click(mine.carousel.arrow_right)
		26:
			_mouse_log["after_my_right"] = _carousel_pages(scene)
			_mouse_click(theirs.carousel.arrow_right)
		32:
			_mouse_log["after_other_right"] = _carousel_pages(scene)
			_mouse_click(mine.carousel.arrow_left)
		38:
			_mouse_log["after_my_left"] = _carousel_pages(scene)
			_mouse_log["other_popup_before"] = theirs.item_popup.visible
			var my_items = scene._get_shop_items_container(me)._shop_items
			if my_items.size() > 0 and is_instance_valid(my_items[0]):
				set_meta("bt_mouse_hover", my_items[0]._button)
				_mouse_move(my_items[0])
		46:
			_mouse_log["my_popup_after_hover"] = mine.item_popup.visible
			_mouse_log["my_focus_on_hovered_item"] = has_meta("bt_mouse_hover") and Utils.get_focus_emulator(me).focused_control == get_meta("bt_mouse_hover")
			set_meta("bt_mouse_other_focus", Utils.get_focus_emulator(other).focused_control)
			var their_items = scene._get_shop_items_container(other)._shop_items
			if their_items.size() > 0 and is_instance_valid(their_items[0]):
				_mouse_move(their_items[0])
		54:
			_mouse_log["other_popup_after_hover"] = theirs.item_popup.visible
			_mouse_log["other_focus_unchanged_after_hover"] = Utils.get_focus_emulator(other).focused_control == get_meta("bt_mouse_other_focus")
			_mouse_log["go_pressed_at_reroll"] = [scene._player_pressed_go_button[me], scene._player_pressed_go_button[other]]
			_mouse_log["gold_before_reroll"] = [RunData.get_player_gold(me), RunData.get_player_gold(other)]
			_mouse_click(scene._get_reroll_button(other))
		62:
			_mouse_log["gold_after_other_reroll"] = [RunData.get_player_gold(me), RunData.get_player_gold(other)]
			_mouse_click(scene._get_reroll_button(me))
		74:
			_mouse_log["gold_after_my_reroll"] = [RunData.get_player_gold(me), RunData.get_player_gold(other)]
			_mouse_done[sid] = true
			print("BTMOUSETEST wave=%d me=%d other=%d %s" % [RunData.current_wave, me, other, str(_mouse_log)])


func _mouse_center(control) -> Vector2:
	return control.get_global_rect().position + control.get_global_rect().size * 0.5


# Synthetic mouse events go through Input.parse_input_event (the real OS-event path, delivered
# next frame). Viewport.input() on the root is NOT usable here: the root viewport reads the
# SceneTree-wide "input handled" flag, which only a real input event resets, so once any event
# has been consumed (the FocusEmulators consume most) every later root.input() call skips all
# _input handlers. parse_input_event expects window coordinates, so map the canvas position
# through the root's final (stretch) transform.
func _mouse_send(ev) -> void:
	var canvas_pos: Vector2 = ev.position
	ev.position = get_viewport().get_final_transform().xform(canvas_pos)
	ev.global_position = ev.position
	Input.parse_input_event(ev)


func _mouse_move(control) -> void:
	var ev = InputEventMouseMotion.new()
	ev.position = _mouse_center(control)
	ev.global_position = ev.position
	_mouse_send(ev)


func _mouse_click(control) -> void:
	_mouse_move(control)
	for is_pressed in [true, false]:
		var ev = InputEventMouseButton.new()
		ev.button_index = BUTTON_LEFT
		ev.pressed = is_pressed
		ev.position = _mouse_center(control)
		ev.global_position = ev.position
		_mouse_send(ev)


# --bt-icon-test: once per co-op shop (after 30 frames) and once per level-up chooser, count the
# key-hint icons (InputIcon, CoopShopHint) that are visible but have no texture, per player panel.
func _icon_test_tick() -> void:
	var scene = get_tree().current_scene
	if scene == null or RunData.get_player_count() < 1:
		return
	var containers = []
	var where = ""
	if scene.name == "CoopShop":
		where = "shop"
		for pi in RunData.get_player_count():
			containers.push_back(scene._get_coop_player_container(pi))
	elif scene.name == "Main" and ("_coop_upgrades_ui" in scene) and is_instance_valid(scene._coop_upgrades_ui) and scene._coop_upgrades_ui.visible:
		where = "levelup"
		for pi in RunData.get_player_count():
			containers.push_back(scene._coop_upgrades_ui._get_player_container(pi))
	else:
		return
	var key = "%s:%d:%d" % [where, scene.get_instance_id(), RunData.current_wave]
	if _icon_done.has(key):
		return
	var frames = _icon_done.get(key + ":f", 0) + 1
	_icon_done[key + ":f"] = frames
	if frames < 30:
		return
	_icon_done[key] = true
	var parts = []
	for pi in containers.size():
		var counts = {"icons": 0, "empty": 0, "empty_names": []}
		_icon_count(containers[pi], counts)
		parts.push_back("p%d icons=%d empty=%d %s" % [pi, counts["icons"], counts["empty"], str(counts["empty_names"])])
		print("BTICONTEST %s wave=%d players=%d %s" % [where, RunData.current_wave, RunData.get_player_count(), parts[pi]])
	var ct = CoopService.connected_players
	print("BTICONTEST %s wave=%d connected_players=%s select=%s ban=%s info=%s" % [where, RunData.current_wave, str(ct), str(CoopService.get_player_key_texture("ui_select", 0)), str(CoopService.get_player_key_texture("ui_coop_ban", 0)), str(CoopService.get_player_key_texture("ui_info", 0))])


func _icon_count(node, counts: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	var rect = null
	if node is InputIcon:
		rect = node
	elif node is CoopShopHint:
		rect = node._key_icon
	if rect != null and rect.is_visible_in_tree():
		counts["icons"] += 1
		if rect.texture == null:
			counts["empty"] += 1
			counts["empty_names"].push_back(str(node.name))
	for child in node.get_children():
		_icon_count(child, counts)


# --bt-combine=<tier>[,alias][,curse][,hidden] -- reproduce the reported shop crash in ONE
# process. The reporter narrowed it to common (tier 1) weapons, and never with a cursed copy
# involved; since nothing in this mod branches on weapon quality, that points at WHICH TWO
# OBJECTS are being merged rather than at the tier. Each modifier reconstructs one candidate:
#
#   <tier>  common | uncommon | rare -- retests "grey only" directly.
#   alias   push the SAME ItemService resource twice instead of two RunData duplicates. This
#           is the state a CLIENT is left in by _weapon_selection_completed
#           (weapon_selection.gd:171), and the only way to produce it without a second
#           machine. Mutually exclusive with curse, which replaces a copy.
#   mixed   one aliased reference plus one add_weapon duplicate -- the reporter's actual
#           case, a starting weapon combined with a shop-bought copy of itself. Takes
#           precedence over alias when both are given.
#   curse   curse one copy, giving the two different stats -- the case that never crashed for
#           the reporter, and the case RunData.remove_weapon can tell apart, since
#           ItemService.is_same_weapon compares stats and not my_id.
#   hidden  force MOUSE_MODE_HIDDEN. Vanilla _combine_weapon re-focuses the new weapon only
#           in that mode, so without it a freed inventory element can stay in the focus
#           emulator for _focus_dictionary_for_player to read (candidate 3). 1.5.2 is the
#           release that gave the shop a mouse, which is when this became reachable.
#
# Each step prints BEFORE it acts, so a hard process exit leaves the step it died on as the
# last line of the log. That matters because a GDScript null dereference prints an error and
# carries on -- whatever takes the process down will not announce itself.
func _combine_tick() -> void:
	var scene = get_tree().current_scene
	if scene == null or scene.name != "CoopShop":
		return
	var sid = scene.get_instance_id()
	if sid != _combine_scene:
		_combine_scene = sid
		_combine_frames = 0
		return
	if _combine_done.has(sid):
		return
	_combine_frames += 1
	# Let the shop settle first: panels built, focus placed, first shop state sent.
	if _combine_frames != 40:
		return
	_combine_done[sid] = true
	_combine_run(scene)


func _combine_run(scene) -> void:
	var parts = _combine_spec.split(",", false)
	var tier_name = str(parts[0]) if parts.size() > 0 else "common"
	var tier_by_name = {"common": 0, "uncommon": 1, "rare": 2}
	var tier = int(tier_by_name[tier_name]) if tier_by_name.has(tier_name) else 0
	var want_alias = false
	var want_mixed = false
	var want_curse = false
	var want_hidden = false
	var want_upgrade = false
	for i in range(1, parts.size()):
		var p = str(parts[i])
		if p == "alias":
			want_alias = true
		elif p == "mixed":
			want_mixed = true
		elif p == "curse":
			want_curse = true
		elif p == "hidden":
			want_hidden = true
		elif p == "upgrade":
			want_upgrade = true

	var base = _combine_pick_weapon(tier)
	if base == null:
		_bt_trace("BTCOMBINE abort: no combinable weapon found at tier %d" % tier)
		return
	_bt_trace("BTCOMBINE spec=%s tier=%s(%d) alias=%s curse=%s hidden=%s weapon=%s upgrades_into=%s" % [
		_combine_spec, tier_name, tier, str(want_alias), str(want_curse), str(want_hidden),
		str(base.my_id), str(base.upgrades_into.my_id)])

	var weapons : Array = RunData.players_data[0].weapons
	_bt_trace("BTCOMBINE before: count=%d %s" % [weapons.size(), str(_combine_ids(weapons))])

	if want_mixed:
		# The reporter's actual crashing case: a STARTING weapon (which on a client is the
		# ItemService resource itself, un-duplicated and with effects never applied) plus a
		# shop-bought copy, which did go through add_weapon. The two differ in identity but
		# not in stats, so is_same_weapon cannot tell them apart while object equality can.
		weapons.push_back(base)
		var d = RunData.add_weapon(base, 0)
		_bt_trace("BTCOMBINE gave 1 ALIASED ref (id=%d) + 1 duplicate (id=%d)" % [
			base.get_instance_id(), d.get_instance_id()])
	elif want_alias:
		# Deliberately NOT add_weapon: the resource itself, twice, with no duplicate and no
		# apply_item_effects -- byte for byte the client's post-selection state for a
		# character whose two starting weapons are the same.
		weapons.push_back(base)
		weapons.push_back(base)
		_bt_trace("BTCOMBINE gave 2 ALIASED refs (same object, id=%d)" % base.get_instance_id())
	else:
		var a = RunData.add_weapon(base, 0)
		var b = RunData.add_weapon(base, 0)
		_bt_trace("BTCOMBINE gave 2 duplicates (ids=%d,%d)" % [a.get_instance_id(), b.get_instance_id()])

	if want_curse:
		var dlc = ItemService.get_dlc_data_by_id("abyssal_terrors")
		var last = weapons.size() - 1
		if dlc != null and dlc.has_method("curse_item"):
			weapons[last] = dlc.curse_item(weapons[last], 0, true, 0.0)
			_bt_trace("BTCOMBINE cursed the second copy via dlc.curse_item")
		else:
			weapons[last].is_cursed = true
			_bt_trace("BTCOMBINE no curse_item on the dlc; set is_cursed directly")

	var gear = scene._get_gear_container(0)
	gear.set_weapons_data(RunData.get_player_weapons(0))
	var target = null
	for el in gear.weapons_container._elements.get_children():
		if el.item != null and str(el.item.my_id) == str(base.my_id) and not el.item.is_cursed:
			target = el.item
			break
	if target == null:
		# Every copy cursed (or none landed): combine whatever carries the right id.
		for el in gear.weapons_container._elements.get_children():
			if el.item != null and str(el.item.my_id) == str(base.my_id):
				target = el.item
				break
	if target == null:
		_bt_trace("BTCOMBINE abort: the pair is not in the gear container after refresh")
		return

	var prev_mouse = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if want_hidden else Input.MOUSE_MODE_VISIBLE)
	var focused = Utils.get_focus_emulator(0).focused_control
	_bt_trace("BTCOMBINE armed: weapons=%s mouse_mode=%d focus_valid=%s target_instance=%d" % [
		str(_combine_ids(RunData.get_player_weapons(0))), Input.get_mouse_mode(),
		str(focused != null and is_instance_valid(focused)), target.get_instance_id()])

	_bt_trace("BTCOMBINE identity before: %s" % _combine_identity(scene))

	if want_upgrade:
		# nb_to_remove == 1: one weapon in, the upgrade out, and NONE of the second-copy
		# search and removal that a normal combine does afterwards. Without that cleanup any
		# disagreement between the container (which matches by reference) and players_data
		# (which matches by stats) is the end state and survives the rest of the run.
		_bt_trace("BTCOMBINE calling _combine_weapon(.., is_upgrade=true) NOW")
		scene._combine_weapon(target, 0, true)
	else:
		_bt_trace("BTCOMBINE calling _on_item_combine_button_pressed NOW")
		scene._on_item_combine_button_pressed(target, 0)
	_bt_trace("BTCOMBINE SURVIVED the combine call")
	_bt_trace("BTCOMBINE after: %s" % str(_combine_ids(RunData.get_player_weapons(0))))
	_bt_trace("BTCOMBINE identity after: %s" % _combine_identity(scene))

	Input.set_mouse_mode(prev_mouse)

	# The host's own combine path ends in request_shop_update -> send_shop_state, which walks
	# the gear the combine just rebuilt and reads the focus emulator. Force one more so a
	# crash in the SEND rather than the combine is attributed correctly.
	_bt_trace("BTCOMBINE forcing a shop state send")
	var sc = get_node_or_null("/root/SteamConnection")
	if sc != null:
		sc.request_shop_update([0])
		# var2bytes + GZIP is the only native crossing in the whole shop path, and
		# last_packet_bytes is set there BEFORE any send is attempted -- so this is the real
		# compressed packet size even when there is no peer to send it to. The per-player
		# loop in send_shop_state means a two-player shop carries two full player dicts.
		_bt_trace("BTCOMBINE shop packet: players=%d compressed_bytes=%d" % [
			RunData.get_player_count(), sc.last_packet_bytes])
	_bt_trace("BTCOMBINE SURVIVED the shop state send -- spec=%s COMPLETE" % _combine_spec)


# First combinable weapon at `tier`, preferring a stable, well-known one so repeat runs and
# the two machines talk about the same weapon.
func _combine_pick_weapon(tier: int):
	var fallback = null
	for w in ItemService.weapons:
		if w == null or w.tier != tier or w.upgrades_into == null:
			continue
		if "pistol" in str(w.my_id) or "knife" in str(w.my_id):
			return w
		if fallback == null:
			fallback = w
	return fallback


# The container matches weapons by REFERENCE (inventory.gd:158 under deep_comparison) while
# RunData.remove_weapon matches by STATS (ItemService.is_same_weapon). Those are different
# predicates, so the two sides can end up holding different objects while agreeing on the
# count -- which a my_id listing cannot show. Print instance ids from both sides instead.
func _combine_identity(scene) -> String:
	var pd := []
	for w in RunData.get_player_weapons(0):
		if w == null:
			pd.push_back("<null>")
		else:
			pd.push_back("%s#%d" % [str(w.my_id), w.get_instance_id()])
	var ui := []
	var gear = scene._get_gear_container(0)
	for el in gear.weapons_container._elements.get_children():
		if el.item == null:
			ui.push_back("<null>")
		elif el.is_queued_for_deletion():
			ui.push_back("%s#%d(freeing)" % [str(el.item.my_id), el.item.get_instance_id()])
		else:
			ui.push_back("%s#%d" % [str(el.item.my_id), el.item.get_instance_id()])
	return "players_data=%s container=%s" % [str(pd), str(ui)]


func _combine_ids(weapons: Array) -> Array:
	var out := []
	for w in weapons:
		if w == null:
			out.push_back("<null>")
		else:
			out.push_back("%s%s" % [str(w.my_id), "(cursed)" if w.is_cursed else ""])
	return out

const COMBINE_TRACE_PATH := "user://bt_combine_trace.log"

# Append-and-close on EVERY line. A redirected stdout buffer loses its tail when the process
# dies abruptly, which is precisely the case --bt-combine exists to catch: the first two
# fake-peer runs looked like they died on the opening heartbeat when in fact the log simply
# stopped there. Closing the file each call is slow and completely reliable, and this is a
# test harness, so reliable wins.
func _bt_trace(line: String) -> void:
	print(line)
	var f := File.new()
	var mode = File.READ_WRITE if f.file_exists(COMBINE_TRACE_PATH) else File.WRITE
	if f.open(COMBINE_TRACE_PATH, mode) != OK:
		return
	f.seek_end()
	f.store_line("%s %s" % [_wall_clock(), line])
	f.close()


func _bt_trace_reset() -> void:
	var f := File.new()
	if f.open(COMBINE_TRACE_PATH, File.WRITE) == OK:
		f.store_line("=== bt_combine trace opened ===")
		f.close()
