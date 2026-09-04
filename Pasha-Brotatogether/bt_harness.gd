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


func _ready() -> void:
	for a in OS.get_cmdline_args():
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
	if _mode == "":
		set_process(false)
		return
	_local_idx = 0 if _mode == "host" else 1
	if _autoplay:
		# Soak runs are unattended: nobody dodges, so players die by wave 1-3 and the host's
		# run-lost path tears the lobby down (leave_game_lobby). Make players invulnerable
		# (DebugService -> RunData.reset copies it -> player disables its hurtbox). Only set
		# when the harness is armed with --bt-autoplay; normal play is untouched.
		DebugService.invulnerable = true
		print("BTHARNESS autoplay: DebugService.invulnerable = true (soak survivability)")
	print("BTHARNESS armed mode=%s join_name=%s autoplay=%s local_idx=%d" % [_mode, _join_name, str(_autoplay), _local_idx])
	# Keep ticking while the tree is paused so the heartbeat can report a pause/freeze.
	pause_mode = Node.PAUSE_MODE_PROCESS


func _process(_delta: float) -> void:
	_hb_tick()
	var sc = get_node_or_null("/root/SteamConnection")
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
		sc.create_new_game_lobby(_friends_only)
	else:
		if not sc.is_connected("game_lobby_found", self, "_on_lobby_found"):
			var _c = sc.connect("game_lobby_found", self, "_on_lobby_found")
		# Retry the one-shot search until we actually join -- the host lobby may not be
		# OPEN yet at our first search, or a single search may miss the window.
		var tries = 0
		while not _joined and tries < 40:
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
	# Post-wave chooser lives INSIDE Main (no scene change), so it needs a per-frame poll
	# rather than the instance-keyed once-per-scene dispatch below.
	if scene.name == "Main":
		_ap_postwave_tick(sc, scene)
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
		scene._set_selected_element(_local_idx)
		print("BTHARNESS autoplay %s: _set_selected_element(%d) called" % [kind, _local_idx])
	if sc.is_host():
		# Do NOT advance until the client is present -- advancing calls
		# send_character_selection_completed, which sets lobby_status=CLOSED and hides
		# the lobby from the client's OPEN-only search before it can join.
		var waited = 0
		while RunData.get_player_count() < 2 and waited < 120:
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
	if ("_latest_focused_element" in scene) and typeof(scene._latest_focused_element) == TYPE_ARRAY and scene._latest_focused_element.size() > 0:
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
	print("BTHARNESS hb %s scene=%s paused=%s wave=%d wave_time=%s chooser=%s lobby=%d seq=%s net=%s cli=%s" % [_wall_clock(), sname, str(tree.paused), RunData.current_wave, wave_time, chooser, lobby, seq, net, cli])
