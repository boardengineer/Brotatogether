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
	if _mode == "":
		set_process(false)
		return
	_local_idx = 0 if _mode == "host" else 1
	print("BTHARNESS armed mode=%s join_name=%s autoplay=%s local_idx=%d" % [_mode, _join_name, str(_autoplay), _local_idx])


func _process(_delta: float) -> void:
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
	if _autoplay:
		_autoplay_tick(sc)


func _drive(sc) -> void:
	print("BTHARNESS entering multiplayer menu")
	var _e = get_tree().change_scene(MP_MENU_SCENE)
	yield(get_tree().create_timer(1.0), "timeout")
	if _mode == "host":
		print("BTHARNESS create_new_game_lobby")
		sc.create_new_game_lobby()
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
