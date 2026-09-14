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
var _armed := false        # any --bt-* flag present; otherwise the harness is fully inert
var _rc_lock := []          # --bt-lock=2,3: host locks these slots once the lobby exists
var _rc_lock_done := false
var _rc_kick_slot := -1     # --bt-kick=<slot>:<secs>: host kicks that slot <secs> after it is seated
var _rc_kick_delay := 0.0
var _rc_kick_since := -1.0
var _rc_kick_done := false
var _join_name := ""
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
var _mortal := false     # --bt-mortal: players can actually die (no DebugService.invulnerable)


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
	if _mode == "":
		set_process(false)
		return
	_local_idx = 0 if _mode == "host" else 1
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
	if sc != null and _mode == "host":
		_rc_tick(sc, _delta)
	if _key_test:
		_key_test_tick()
	if _mouse_test:
		_mouse_test_tick()
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
	print("BTHARNESS joining id=%s name=%s" % [str(lobby_id), str(lobby_name)])
	Steam.joinLobby(lobby_id)


# --- Autoplay: drive each selection screen once, after it has stabilized ---------
func _autoplay_tick(sc) -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	if _bots and CoopService.get("is_bot_by_index") != null and _local_idx < CoopService.is_bot_by_index.size():
		# Idempotent re-assert: mode switches call clear_coop_players() which wipes the flags.
		CoopService.is_bot_by_index[_local_idx] = true
	# Post-wave chooser lives INSIDE Main (no scene change), so it needs a per-frame poll
	# rather than the instance-keyed once-per-scene dispatch below.
	if scene.name == "Main":
		_ap_postwave_tick(sc, scene)
		_die_tick(sc, scene)
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
		scene._set_selected_element(_local_idx)
		print("BTHARNESS autoplay %s: _set_selected_element(%d) called" % [kind, _local_idx])
		if (kind == "character" or kind == "weapon") and _local_idx < RunData.players_data.size():
			var cc = RunData.players_data[_local_idx].current_character
			print("BTHARNESS autoplay character committed: %s" % (cc.my_id if cc != null else "<null>"))
	if sc.is_host():
		# Do NOT advance until the client is present -- advancing calls
		# send_character_selection_completed, which sets lobby_status=CLOSED and hides
		# the lobby from the client's OPEN-only search before it can join.
		var waited = 0
		while RunData.get_player_count() < 2 and waited < 240:
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
	if _bots:
		# GO is a TOGGLE: with --bt-bots the AutoBattler autoshop presses GO itself at
		# the end of its buy/reroll flow, and a second press from the harness UN-readies
		# the player -- a 50/50 wedge per shop depending on ordering (seen live wave 3).
		# The autoshop owns GO on bot runs; the harness stays out of it.
		print("BTHARNESS autoplay shop: bots own GO, harness skipping")
		return
	if _local_idx < pc and scene.has_method("_on_GoButton_pressed"):
		scene._on_GoButton_pressed(_local_idx)
		print("BTHARNESS autoplay shop: GO pressed for player %d" % _local_idx)


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
		net = "%d/%d" % [sc.last_packet_bytes, sc.unreliable_fallbacks]
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
	# pl=alive/total players (both sides). A client whose 'alive' stays above the host's
	# after a death = BATCHED_PLAYER_DEATHS not applied; run=L/W once a run end is known.
	var pl = "n/a"
	if scene != null and ("_players" in scene):
		var alive = 0
		for p in scene._players:
			if is_instance_valid(p) and not p.dead:
				alive += 1
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
				hp_parts.append("%d/%d" % [p.current_stats.health, p.max_stats.health])
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
