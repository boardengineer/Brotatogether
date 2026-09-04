extends Node

const GLOBAL_CHAT_TYPE := "BROTATOGETHER_GLOBAL_CHAT"
const GAME_LOBBY_TYPE := "BROTATOGETHER_GAME_LOBBY"

# Compatibility fingerprint keys stamped into a game lobby's Steam metadata by the host and
# checked by a joining client (compat_mismatch_reason / attempt_join_game_lobby). A client whose
# game version, active-DLC set, or loaded-mod set (id:version) differs is refused before the run
# starts, so a version/content skew can never desync a co-op game.
const COMPAT_KEY_GAME_VERSION := "bt_game_version"
const COMPAT_KEY_DLC := "bt_dlc"
const COMPAT_KEY_MODS := "bt_mods"

enum PlayerStatus {CONNECTING, LOBBYING, PLAYING, SELF}

# Channels will be mapped 1:1 with channels
enum MessageType {
	# Start a latency ping. client -> host
	MESSAGE_TYPE_PING,

	# Respond to a latency ping. host -> client
	MESSAGE_TYPE_PONG,

	# Report the results of a latency ping. client -> host
	MESSAGE_TYPE_LATENCY_REPORT,

	# Report the status of all players to clients. host -> client
	MESSAGE_TYPE_PLAYER_STATUS,

	# Report a change in focus of the currently selected character. client -> host
	MESSAGE_TYPE_CHARACTER_FOCUS,

	# Report that a character has been selected (clicked). client -> host
	MESSAGE_TYPE_CHARACTER_SELECTED,

	MESSAGE_TYPE_CHARACTER_SELECTION_COMPLETED,

	# Report the state of all player selections so far
	MESSAGE_TYPE_CHARACTER_LOBBY_UPDATE,

	# Report a change in focus of the currently selected weapon.  client -> host
	MESSAGE_TYPE_WEAPON_FOCUS,

	# Report that a weapon has been selected (clicked). client -> host
	MESSAGE_TYPE_WEAPON_SELECTED,

	# Report the state of all player selections for weapons.
	MESSAGE_TYPE_WEAPON_LOBBY_UPDATE,

	MESSAGE_TYPE_WEAPON_SELECTION_COMPLETED,

	# Report that the host has focused on a difficulty
	MESSAGE_TYPE_DIFFICULTY_FOCUSED,

	# Report that the host has selected a difficulty
	MESSAGE_TYPE_DIFFICULTY_PRESSED,

	MESSAGE_TYPE_SHOP_ITEM_FOCUS,

	MESSAGE_TYPE_SHOP_INVENTORY_ITEM_FOCUS,

	MESSAGE_TYPE_SHOP_GO_BUTTON_UPDATED,

	MESSAGE_TYPE_SHOP_WEAPON_DISCARD,

	MESSAGE_TYPE_SHOP_CLOSE_POPUP,

	MESSAGE_TYPE_SHOP_BUY_ITEM,

	MESSAGE_TYPE_SHOP_REROLL,

	MESSAGE_TYPE_SHOP_LOCK_ITEM,

	MESSAGE_TYPE_SHOP_UNLOCK_ITEM,

	MESSAGE_TYPE_SHOP_COMBINE_WEAPON,

	MESSAGE_TYPE_SHOP_LOBBY_UPDATE,

	MESSAGE_TYPE_LEAVE_SHOP,

	MESSAGE_TYPE_HOST_ROUND_START,

	MESSAGE_TYPE_MAIN_STATE,

	MESSAGE_TYPE_CLIENT_POSITION,

	MESSAGE_TYPE_CLIENT_FOCUS_MAIN_SCENE,

	MESSAGE_TYPE_MAIN_SCENE_REROLL_BUTTON_PRESSED,

	MESSAGE_TYPE_MAIN_SCENE_CHOOSE_UPGRADE_PRESSED,

	MESSAGE_TYPE_MAIN_SCENE_TAKE_BUTTON_PRESSED,

	MESSAGE_TYPE_MAIN_SCENE_DISCARD_BUTTON_PRESSED,

	MESSAGE_TYPE_HOST_ENTERED_SHOP,

	# Reliable event/delta channel split out of MAIN_STATE: enemy deaths, spawn births,
	# hit effects/particles/flashes, floating text, sounds and explosions -- one-shot
	# deltas that must arrive. Lets the high-rate positional MAIN_STATE snapshot go
	# UNRELIABLE (newest-wins) without head-of-line blocking. host -> client
	MESSAGE_TYPE_MAIN_STATE_EVENTS,
}

var global_chat_lobby_id : int = -1
var steam_id : int

var game_lobby_id : int = -1
var lobby_members : Array = []
var lobby_member_names : Array = []

# Messages to be displayed in the global lobby chat next time its entered
var pending_system_messages : Array = []

# Player latencies will be populated as people join and start sending statuses.
var player_latencies : Dictionary = {}
var game_lobby_owner_id : int = -1

var is_querying_global_chat := false

var is_creating_global_chat_lobby : bool = false

# Regularly ensure that we're connected to the lowest id global chat channel.
var global_chat_check_timer : Timer

# Regularly all players to make sure they're still connected and to update
# latency readings.
#
# Clients will use this timer to initiate ping exchanges.
#
# The Host will use this timer to send latency status to all clients.
var ping_timer : Timer

# Random string to map ping requests
var ping_key
var ping_start_time_msec = -1

# Steam P2P unreliable sends fail (return false, silently) above ~1200 B (UDP MTU); reliable
# allows up to 1 MB. Snapshots that outgrow the MTU are sent RELIABLE instead of being lost.
const UNRELIABLE_MAX_BYTES : int = 1150
var last_packet_bytes : int = 0          # compressed size of the last packet sent (diagnostics)
var unreliable_fallbacks : int = 0       # how many snapshots had to fall back to reliable
var _send_fail_logged := {}              # channel -> true once a failed send was logged

# Emitted when a game-lobby join is refused for a version/DLC/mod mismatch. `reason` is a
# human-readable, multi-line description of what differs; the multiplayer menu shows it.
signal join_blocked (reason)

# Received a global chat, should be connected to chat panels to display the new chat message.
signal global_chat_received (username, message)

# Received a lobby chat, should be connected to lobby chat panels ot display the new chat message.
signal game_lobby_chat_received (username, message)

# A new game lobby was found, display the game lobby, probably with a join button
signal game_lobby_found (lobby_id, lobby_name)

# A player has entered or left the lobby
signal lobby_players_updated()

# A player changed the focus in the character selection screen.  Connect to update the ui
signal player_focused_character(player_index, character)

# A player has confrimed their character selection.  Connect to update the ui
signal player_selected_character(player_index, character)

signal request_character_lobby_update()

# Clients should update to this state of the character selection screen.  Clients should only update
# others' character selections to maintain responsive control over their own UI.
signal character_lobby_update(player_characters, has_player_selected)

signal character_selection_complete(some_player_has_weapon_slots, selected_characters)

# A player changed the focus in the weapon selection screen.  Connect to update the ui
signal player_focused_weapon(player_index, weapon)

# A player confirmed their selected weapon.  Connect to update the ui
signal player_selected_weapon(player_index, weapon)

# Client should update to this state of the weapons selection screen.  Clients should ignore updates
# To their own state
signal weapon_lobby_update(player_weapons, has_player_selected)

signal weapon_selection_completed(selected_weapons)

# Clients shoulda update to this state of the difficulty selection screen.  There is only one
# difficulty item to select and it controlled by the host.
signal difficulty_focused(lobby_difficulty)

# The difficulty was selected, proceed out of the difficulty selection screen
signal difficulty_selected(lobby_difficulty)

# For shop item focus
signal client_shop_focus_updated(shop_item_string, player_index)

# For inventory (item or weapon) focus
signal client_shop_focus_inventory_element(element_dict, player_index)

signal client_shop_buy_item(item_string, player_index)

signal client_shop_reroll(player_index)

signal client_shop_go_button_pressed(current_state, player_index)

signal client_shop_lock_item(item_string, wave_value, player_index)

signal client_shop_unlock_item(item_string, player_index)

signal client_shop_combine_weapon(weapon_string, is_upgrade, player_index)

signal client_shop_discard_weapon(weapon_string, player_index)

signal client_shop_requested()

signal shop_lobby_update(shop_dict)

signal client_status_received(status_dict, player_index)

signal host_starts_round()

signal close_popup()

signal receive_leave_shop()

signal state_update(state_dict)

signal state_events(events_dict)

signal client_position(client_position_dict, player_index)

signal client_menu_focus(client_menu_focus_dict, player_index)

signal client_main_scene_reroll_button_pressed(player_index)

signal client_main_scene_choose_upgrade_pressed(upgrade_data_dict, player_index)

signal client_main_scene_take_button_pressed(player_index)

signal client_main_scene_discard_button_pressed(player_index)

signal host_entered_shop()

func _ready():
	if not Steam.loggedOn():
		return

	var _err

	_err = Steam.connect("lobby_match_list", self, "_on_lobby_match_list")
	_err = Steam.connect("lobby_created", self, "_on_lobby_created")
	_err = Steam.connect("lobby_joined", self, "_on_lobby_joined")
	_err = Steam.connect("lobby_message", self, "_on_lobby_message")
	_err = Steam.connect("lobby_chat_update", self, "_on_lobby_chat_update")
	_err = Steam.connect("p2p_session_request", self, "_on_p2p_session_request")
	_err = Steam.connect("p2p_session_connect_fail", self, "_on_p2p_session_connect_fail")

	global_chat_check_timer = Timer.new()
	_err = global_chat_check_timer.connect("timeout", self, "_request_global_chat_search")
	add_child(global_chat_check_timer)
	global_chat_check_timer.start(3.0)

	ping_timer = Timer.new()
	_err = ping_timer.connect("timeout", self, "_ping_timer_timeout")
	add_child(ping_timer)
	ping_timer.start(2.0)

	_request_global_chat_search()
	steam_id = Steam.getSteamID()


func _physics_process(_delta : float) -> void:
	Steam.run_callbacks()

	if game_lobby_id > 0:
		read_p2p_packet()


func send_global_chat_message(message : String) -> void:
	var _err = Steam.sendLobbyChatMsg(global_chat_lobby_id, message)


func send_lobby_chat_message(message : String) -> void:
	var _err = Steam.sendLobbyChatMsg(game_lobby_id, message)


func _on_lobby_match_list(lobbies: Array) -> void:
	var found_global_chat_lobby : bool = false
	var min_chat_lobby_id : int = -1

	for lobby_id in lobbies:
		var lobby_data : Dictionary = Steam.getAllLobbyData(lobby_id)

		var is_game_lobby : bool = false
		var game_lobby_name : String

		for kvpair_index in lobby_data:
			var key = lobby_data[kvpair_index]["key"]
			var value = lobby_data[kvpair_index]["value"]
			if key.to_lower() == "lobby_type":
				if value == GLOBAL_CHAT_TYPE:
					if not found_global_chat_lobby:
						min_chat_lobby_id = lobby_id

					if lobby_id < min_chat_lobby_id:
						min_chat_lobby_id = lobby_id

					found_global_chat_lobby = true
				elif value == GAME_LOBBY_TYPE:
					is_game_lobby = true
			elif key == "lobby_name":
				game_lobby_name = value

		if is_game_lobby:
			emit_signal("game_lobby_found", lobby_id, game_lobby_name)

	if found_global_chat_lobby:
		if min_chat_lobby_id != global_chat_lobby_id:
			Steam.joinLobby(min_chat_lobby_id)
	else:
		if global_chat_lobby_id == -1 and not is_creating_global_chat_lobby:
			is_creating_global_chat_lobby = true
			Steam.createLobby(Steam.LOBBY_TYPE_INVISIBLE, 250)


func leave_game_lobby() -> void:
	if game_lobby_id > 0:
		lobby_members.clear()
		lobby_member_names.clear()

		Steam.leaveLobby(game_lobby_id)
		game_lobby_id = 0


func _on_lobby_created(connect: int, created_lobby_id: int) -> void:
	print("Created Lobby")
	if connect == 1:
		if is_creating_global_chat_lobby:
			print("Lobby created for chat: ", created_lobby_id)
			is_creating_global_chat_lobby = false
			global_chat_lobby_id = created_lobby_id
			var _err = Steam.setLobbyData(created_lobby_id, "lobby_type", GLOBAL_CHAT_TYPE)
		else:
			print("Lobby created for game: ", created_lobby_id)
			game_lobby_id = created_lobby_id
			game_lobby_owner_id = Steam.getLobbyOwner(game_lobby_id) # This should be me but query to make sure
			var _err = Steam.setLobbyData(created_lobby_id, "lobby_type", GAME_LOBBY_TYPE)
			_err = Steam.setLobbyData(created_lobby_id,"lobby_name", Steam.getFriendPersonaName(Steam.getSteamID()))
			_err = Steam.setLobbyData(created_lobby_id,"lobby_status", "OPEN")
			# Stamp our version/DLC/mods so joining clients can refuse an incompatible game.
			_stamp_compat_lobby_data(created_lobby_id)


func _request_global_chat_search() -> void:
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("lobby_type", GLOBAL_CHAT_TYPE, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()


func request_lobby_search() -> void:
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("lobby_type", GAME_LOBBY_TYPE, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter("lobby_status", "OPEN", Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	print("Joined Lobby ", lobby_id)
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		var lobby_data : Dictionary = Steam.getAllLobbyData(lobby_id)
		for kvpair_index in lobby_data:
			var key = lobby_data[kvpair_index]["key"]
			var value = lobby_data[kvpair_index]["value"]
			print("Lobby Data: ", lobby_id, " ----- ", key, ":", value)
			if key.to_lower() == "lobby_type":
				if value == GLOBAL_CHAT_TYPE:
					global_chat_lobby_id = lobby_id
				elif value == GAME_LOBBY_TYPE:
					# Backstop for join paths that skip attempt_join_game_lobby (e.g. a Steam
					# invite): re-verify compatibility now that we're in and the data is present.
					var reason := compat_mismatch_reason(lobby_id)
					if reason != "":
						pending_system_messages.push_back("Cannot join lobby -- incompatible:\n" + reason)
						Steam.leaveLobby(lobby_id)
						var _e = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_menu.tscn")
						return
					$"/root/BrotogetherOptions".joining_multiplayer_lobby = true
					game_lobby_id = lobby_id
					game_lobby_owner_id = Steam.getLobbyOwner(lobby_id)

					for member_index in Steam.getNumLobbyMembers(lobby_id):
						var member_id = Steam.getLobbyMemberByIndex(lobby_id, member_index)
						lobby_members.push_back(member_id)
						lobby_member_names.push_back(Steam.getFriendPersonaName(member_id))

					print("Changing to Character Selection Screen...")
					var _error = get_tree().change_scene(MenuData.character_selection_scene)
					print("change scene error : ", _error)

					_initiate_ping()


func _on_lobby_chat_update(lobby_id: int, change_id: int, _making_change_id: int, chat_state: int) -> void:
	# Get the user who has made the lobby change
	var changer_name: String = Steam.getFriendPersonaName(change_id)

	# If a player has joined the lobby
	if chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
		if lobby_id == game_lobby_id and game_lobby_id != -1:
			if not lobby_members.has(change_id):
				lobby_members.push_back(change_id)
				lobby_member_names.push_back(changer_name)
				emit_signal("lobby_players_updated")
			print("%s has joined the lobby." % changer_name)

	# Else if a player has left the lobby
	elif chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_LEFT:
		if change_id == game_lobby_owner_id:
			pending_system_messages.push_back("Host left the lobby")
			leave_game_lobby()
			var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_menu.tscn")
		print("%s has left the lobby." % changer_name)

	# Else if a player has been kicked
	elif chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_KICKED:
		print("%s has been kicked from the lobby." % changer_name)

	# Else if a player has been banned
	elif chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_BANNED:
		print("%s has been banned from the lobby." % changer_name)

	# Else there was some unknown change
	else:
		print("%s did... something." % changer_name)


func _on_p2p_session_connect_fail(_steam_id: int, session_error: int) -> void:
	if session_error != 0:
		print_debug("error connecting to p2p session")


func _on_lobby_message(lobby_id : int, user_id : int, buffer : String, _chat_type : int) -> void:
	if lobby_id == global_chat_lobby_id:
		emit_signal("global_chat_received", Steam.getFriendPersonaName(user_id), buffer)
	elif lobby_id == game_lobby_id:
		emit_signal("game_lobby_chat_received", Steam.getFriendPersonaName(user_id), buffer)


# --- Version / DLC / mod compatibility gate --------------------------------------------------

# This client's game version (e.g. "1.1.15.4").
func _compat_game_version() -> String:
	return str(ProgressData.VERSION)


# Sorted comma-joined ACTIVE dlc ids (owned AND not deactivated) -- the content the game is
# actually running. A peer missing or deactivating any of these would desync.
func _compat_dlc_string() -> String:
	var ids := []
	for dlc_id in ProgressData.get_active_dlc_ids():
		ids.push_back(str(dlc_id))
	ids.sort()
	return PoolStringArray(ids).join(",")


# Sorted comma-joined "mod_id:version" for every loaded mod.
func _compat_mods_string() -> String:
	var entries := []
	var all_mods : Dictionary = ModLoaderMod.get_mod_data_all()
	for mod_id in all_mods:
		var md = all_mods[mod_id]
		var ver := "?"
		if md != null and md.manifest != null:
			ver = str(md.manifest.version_number)
		entries.push_back("%s:%s" % [str(mod_id), ver])
	entries.sort()
	return PoolStringArray(entries).join(",")


func _stamp_compat_lobby_data(lobby_id : int) -> void:
	var _e = Steam.setLobbyData(lobby_id, COMPAT_KEY_GAME_VERSION, _compat_game_version())
	_e = Steam.setLobbyData(lobby_id, COMPAT_KEY_DLC, _compat_dlc_string())
	_e = Steam.setLobbyData(lobby_id, COMPAT_KEY_MODS, _compat_mods_string())


# Read a game lobby's compat keys into {key:value}. getAllLobbyData forces a metadata read, so
# this works both pre-join (lobby came from a search) and post-join.
func _lobby_compat_kv(lobby_id : int) -> Dictionary:
	var data : Dictionary = Steam.getAllLobbyData(lobby_id)
	var kv := {}
	for idx in data:
		kv[data[idx]["key"]] = str(data[idx]["value"])
	return kv


# "" if this client is compatible with the host of `lobby_id`, else a multi-line description of
# every mismatch (game version, DLC, mods). An unstamped lobby (older host) is also incompatible.
func compat_mismatch_reason(lobby_id : int) -> String:
	var kv := _lobby_compat_kv(lobby_id)
	var host_version : String = kv.get(COMPAT_KEY_GAME_VERSION, "")
	var host_dlc : String = kv.get(COMPAT_KEY_DLC, "")
	var host_mods : String = kv.get(COMPAT_KEY_MODS, "")

	if host_version == "" and host_dlc == "" and host_mods == "":
		return "The host is running an older version of Brotatogether without compatibility checking. Both players must update to the same version."

	var problems := []
	if host_version != _compat_game_version():
		problems.push_back("Game version differs -- host: %s, you: %s" % [host_version, _compat_game_version()])

	var dlc_diff := _diff_id_lists(host_dlc, _compat_dlc_string())
	if dlc_diff != "":
		problems.push_back("DLC differs -- " + dlc_diff)

	var mods_diff := _diff_mods(host_mods, _compat_mods_string())
	if mods_diff != "":
		problems.push_back("Mods differ -- " + mods_diff)

	return PoolStringArray(problems).join("\n")


# Diff two comma-joined id lists into "host has [X] you lack; you have [Y] host lacks".
func _diff_id_lists(host_csv : String, mine_csv : String) -> String:
	var host_set := {}
	for i in host_csv.split(",", false):
		host_set[i] = true
	var mine_set := {}
	for i in mine_csv.split(",", false):
		mine_set[i] = true
	var host_only := []
	for i in host_set:
		if not mine_set.has(i):
			host_only.push_back(i)
	var mine_only := []
	for i in mine_set:
		if not host_set.has(i):
			mine_only.push_back(i)
	return _format_diff(host_only, mine_only, [])


func _parse_mods(csv : String) -> Dictionary:
	var d := {}
	for entry in csv.split(",", false):
		var idx = entry.find(":")
		if idx == -1:
			d[entry] = ""
		else:
			d[entry.substr(0, idx)] = entry.substr(idx + 1)
	return d


# Diff two "id:version" mod lists: present-on-one-side plus same-id/different-version.
func _diff_mods(host_csv : String, mine_csv : String) -> String:
	var host := _parse_mods(host_csv)
	var mine := _parse_mods(mine_csv)
	var host_only := []
	var mine_only := []
	var ver_diff := []
	for id in host:
		if not mine.has(id):
			host_only.push_back(id)
		elif mine[id] != host[id]:
			ver_diff.push_back("%s (host %s, you %s)" % [id, host[id], mine[id]])
	for id in mine:
		if not host.has(id):
			mine_only.push_back(id)
	return _format_diff(host_only, mine_only, ver_diff)


func _format_diff(host_only : Array, mine_only : Array, ver_diff : Array) -> String:
	if host_only.empty() and mine_only.empty() and ver_diff.empty():
		return ""
	var parts := []
	if not host_only.empty():
		host_only.sort()
		parts.push_back("host has [%s] you lack" % PoolStringArray(host_only).join(", "))
	if not mine_only.empty():
		mine_only.sort()
		parts.push_back("you have [%s] host lacks" % PoolStringArray(mine_only).join(", "))
	if not ver_diff.empty():
		ver_diff.sort()
		parts.push_back("version mismatch: %s" % PoolStringArray(ver_diff).join(", "))
	return PoolStringArray(parts).join("; ")


# Join entry point used by the lobby list. Verifies compatibility BEFORE joining, so an
# incompatible client never enters the host's lobby (no join/leave churn, instant feedback).
func attempt_join_game_lobby(lobby_id : int) -> void:
	var reason := compat_mismatch_reason(lobby_id)
	if reason != "":
		emit_signal("join_blocked", reason)
		return
	Steam.joinLobby(lobby_id)


func create_new_game_lobby() -> void:
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 4)


# Sends data to a receipient or to all others if target_id is -1
func send_p2p_packet(data : Dictionary, message_type : int, target_id = -1, p_send_type : int = -1) -> void:
	# Set the send_type and channel. p_send_type overrides the default RELIABLE delivery
	# (e.g. Steam.P2P_SEND_UNRELIABLE for the high-rate positional state snapshot).
	var send_type: int = p_send_type if p_send_type != -1 else Steam.P2P_SEND_RELIABLE
	var channel: int = message_type

	if game_lobby_id == -1:

		return

	var packet_data: PoolByteArray = PoolByteArray()
	# Compress the PoolByteArray we create from our dictionary  using the GZIP compression method

	var compressed_data: PoolByteArray = var2bytes(data).compress(File.COMPRESSION_GZIP)
	packet_data.append_array(compressed_data)
	last_packet_bytes = compressed_data.size()

	# Unreliable P2P packets are capped at ~1200 B by Steam; an oversize unreliable send
	# returns false and the packet is lost. Fall back to reliable for this packet so a large
	# snapshot still arrives (late beats never).
	if send_type == Steam.P2P_SEND_UNRELIABLE and last_packet_bytes > UNRELIABLE_MAX_BYTES:
		send_type = Steam.P2P_SEND_RELIABLE
		unreliable_fallbacks += 1
		if unreliable_fallbacks == 1 or unreliable_fallbacks % 600 == 0:
			print("BTNET unreliable->reliable fallback #%d channel=%d bytes=%d" % [unreliable_fallbacks, channel, last_packet_bytes])

	if target_id == -1:
		for lobby_member_id in lobby_members:
			if lobby_member_id != steam_id:
				var sent = Steam.sendP2PPacket(lobby_member_id, packet_data, send_type, channel)
				_check_send(sent, channel, send_type, last_packet_bytes)
	else:
		if target_id == steam_id:
			print("WARNING - Attempting to send data to myself:\n", data)
			return

		var sent = Steam.sendP2PPacket(target_id, packet_data, send_type, channel)
		_check_send(sent, channel, send_type, last_packet_bytes)


# Log the first failed send per channel (Steam returns false for oversize/invalid/queue-full)
# so transport failures are never silent again.
func _check_send(sent : bool, channel : int, send_type : int, bytes : int) -> void:
	if sent or _send_fail_logged.has(channel):
		return
	_send_fail_logged[channel] = true
	print("BTNET sendP2PPacket FAILED channel=%d send_type=%d bytes=%d (further failures on this channel not logged)" % [channel, send_type, bytes])


func read_p2p_packet() -> void:
	for channel in MessageType.values():
		var packet_size: int = Steam.getAvailableP2PPacketSize(channel)

		while packet_size > 0:
			var packet : Dictionary = Steam.readP2PPacket(packet_size, channel)

			if packet == null or packet.empty():
				packet_size = 0
				continue

			var sender_id : int = packet["remote_steam_id"]
			var data : Dictionary = bytes2var(packet["data"].decompress_dynamic(-1, File.COMPRESSION_GZIP))

			if channel == MessageType.MESSAGE_TYPE_PING:
				_respond_to_ping(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_PONG:
				_respond_to_pong(data)
			elif channel == MessageType.MESSAGE_TYPE_LATENCY_REPORT:
				_accept_latency_report(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_PLAYER_STATUS:
				_receive_player_statuses(data)
			elif channel == MessageType.MESSAGE_TYPE_CHARACTER_FOCUS:
				_receive_character_focus(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_CHARACTER_SELECTED:
				_receive_character_select(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_CHARACTER_LOBBY_UPDATE:
				_receive_character_lobby_update(data)
			elif channel == MessageType.MESSAGE_TYPE_WEAPON_FOCUS:
				_receive_weapon_focus(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_WEAPON_SELECTED:
				_receive_weapon_select(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_WEAPON_LOBBY_UPDATE:
				_receive_weapon_lobby_update(data)
			elif channel == MessageType.MESSAGE_TYPE_DIFFICULTY_FOCUSED:
				_receive_difficutly_focus_update(data)
			elif channel == MessageType.MESSAGE_TYPE_DIFFICULTY_PRESSED:
				_receive_difficutly_pressed(data)

			# Shop channels
			elif channel == MessageType.MESSAGE_TYPE_SHOP_LOBBY_UPDATE:
				_receive_shop_update(data)
			elif channel == MessageType.MESSAGE_TYPE_SHOP_WEAPON_DISCARD:
				_receive_shop_weapon_discard(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_SHOP_BUY_ITEM:
				_receive_shop_buy_item(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_SHOP_REROLL:
				_receive_shop_reroll(sender_id)
			elif channel == MessageType.MESSAGE_TYPE_SHOP_COMBINE_WEAPON:
				_receive_shop_combine_weapon(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_SHOP_ITEM_FOCUS:
				_receive_shop_item_focus(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_SHOP_GO_BUTTON_UPDATED:
				_receive_shop_go_button_pressed(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_SHOP_LOCK_ITEM:
				_receive_shop_lock_item(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_SHOP_UNLOCK_ITEM:
				_receive_shop_unlock_item(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_CHARACTER_SELECTION_COMPLETED:
				_receive_character_selection_completed(data)
			elif channel == MessageType.MESSAGE_TYPE_WEAPON_SELECTION_COMPLETED:
				_receive_weapon_selection_completed(data)
			elif channel == MessageType.MESSAGE_TYPE_HOST_ROUND_START:
				_receive_host_round_start()
			elif channel == MessageType.MESSAGE_TYPE_SHOP_INVENTORY_ITEM_FOCUS:
				_receive_shop_focus_inventory_element(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_SHOP_CLOSE_POPUP:
				_receive_shop_close_popup()
			elif channel == MessageType.MESSAGE_TYPE_LEAVE_SHOP:
				_receive_leave_shop()

			# Main scene channels
			elif channel == MessageType.MESSAGE_TYPE_MAIN_STATE:
				_receive_game_state(data)
			elif channel == MessageType.MESSAGE_TYPE_MAIN_STATE_EVENTS:
				_receive_game_events(data)
			elif channel == MessageType.MESSAGE_TYPE_CLIENT_POSITION:
				_receive_client_position(data, sender_id)

			## Post-wave menu channels
			elif channel == MessageType.MESSAGE_TYPE_CLIENT_FOCUS_MAIN_SCENE:
				_receive_client_menu_focus(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_MAIN_SCENE_REROLL_BUTTON_PRESSED:
				_receive_main_scene_client_reroll_button_pressed(sender_id)
			elif channel == MessageType.MESSAGE_TYPE_MAIN_SCENE_CHOOSE_UPGRADE_PRESSED:
				_receive_main_scene_client_choose_upgrade_pressed(data, sender_id)
			elif channel == MessageType.MESSAGE_TYPE_MAIN_SCENE_TAKE_BUTTON_PRESSED:
				_receive_main_scene_client_take_button_pressed(sender_id)
			elif channel == MessageType.MESSAGE_TYPE_MAIN_SCENE_DISCARD_BUTTON_PRESSED:
				_receive_main_scene_client_discard_button_pressed(sender_id)
			elif channel == MessageType.MESSAGE_TYPE_HOST_ENTERED_SHOP:
				_receive_host_entered_shop()

			packet_size = Steam.getAvailableP2PPacketSize(channel)


func _generate_ping_key() -> String:
	var characters : String = "abcdefghijklmnopqrstuvwxyz"
	var word : String = ""
	for _i in 5:
		word += characters[randi() % len(characters)]
	return word


func _ping_timer_timeout() -> void:
	if game_lobby_id == -1 or game_lobby_owner_id == -1:
		return

	if steam_id == game_lobby_owner_id:
		_send_player_statuses()
	else:
		_initiate_ping()


func _initiate_ping() -> void:
	if game_lobby_owner_id == -1:
		print("WARNING - Attempting to send ping to unknown lobby host")
		return

	ping_key = _generate_ping_key()
	ping_start_time_msec = Time.get_ticks_msec()

	var data = {
		"PING_KEY": ping_key,
		"CURRENT_SCENE": get_tree().current_scene.name,
	}

	send_p2p_packet(data, MessageType.MESSAGE_TYPE_PING, game_lobby_owner_id)


func _respond_to_ping(data : Dictionary, sender_id : int) -> void:
	if not data.has("PING_KEY"):
		print("WARNING - Ping sent without key")
		return

	emit_signal("client_status_received", data, get_lobby_index_for_player(sender_id))
	send_p2p_packet({"PING_KEY": data["PING_KEY"]}, MessageType.MESSAGE_TYPE_PONG, sender_id)


func _respond_to_pong(data : Dictionary) -> void:
	if not data.has("PING_KEY"):
		print("WARNING - Pong sent without key")
		return

	if data["PING_KEY"] != ping_key:
		print("WARNING - Ping response key doesn't match")
		return

	if ping_start_time_msec == -1:
		print("WARNING - Ping request send without starting timer")
		return

	var current_time_msec = Time.get_ticks_msec()
	var latency_msec = current_time_msec - ping_start_time_msec

	send_p2p_packet({"LATENCY": str(latency_msec)}, MessageType.MESSAGE_TYPE_LATENCY_REPORT, game_lobby_owner_id)


func _accept_latency_report(data : Dictionary, sender_id : int) -> void:
	if not data.has("LATENCY"):
		print("WARNING - Received latency report without result")
		return

	player_latencies[sender_id] = int(data["LATENCY"])


func _send_player_statuses() -> void:
	if game_lobby_id == -1 or game_lobby_owner_id == -1:
		print("WARNING - Attempting to send player latencies to unknown lobby or unknown lobby owner")
		return

	if game_lobby_owner_id != steam_id:
		print("WARNING - Attempting to send player latencies when not the lobby owner")
		return

#	print_debug("sending player latencies : ", player_latencies)

	for player_id in lobby_members:
		if player_id == steam_id:
			continue

		send_p2p_packet({"PLAYER_LATENCIES": player_latencies}, MessageType.MESSAGE_TYPE_PLAYER_STATUS)


func _receive_player_statuses(data : Dictionary) -> void:
	if not data.has("PLAYER_LATENCIES"):
		print("WARNING - player statuses returned without latencies")
		return

	player_latencies = data["PLAYER_LATENCIES"]
#	print_debug("received player latencies: ", player_latencies)


func _on_p2p_session_request(remote_id: int) -> void:
	# Get the requester's name
	var this_requester: String = Steam.getFriendPersonaName(remote_id)
	print("%s is requesting a P2P session" % this_requester)

	# Accept the P2P session; can apply logic to deny this request if needed
	var _err = Steam.acceptP2PSessionWithUser(remote_id)

	# Make the initial handshake
	if not game_lobby_owner_id == steam_id:
		_initiate_ping()


func is_host() -> bool:
	return game_lobby_owner_id == steam_id


# Character select screen functions
func character_focused(character_key : String) -> void:
	if is_host():
		emit_signal("request_character_lobby_update")
	else:
		send_p2p_packet({"CHARACTER": character_key}, MessageType.MESSAGE_TYPE_CHARACTER_FOCUS, game_lobby_owner_id)


func _receive_character_focus(data : Dictionary, sender_id : int) -> void:
	if not data.has("CHARACTER"):
		print("WARNING - received character focus for player ", sender_id)
		return

	if sender_id == -1 or sender_id == steam_id or sender_id == game_lobby_owner_id:
		print("WARNING - received character focus for player ", sender_id)
		return

	var player_index = get_lobby_index_for_player(sender_id)
	if player_index == -1:
		return

	emit_signal("player_focused_character", player_index, data["CHARACTER"])
	emit_signal("request_character_lobby_update")


func character_selected() -> void:
	if is_host():
		emit_signal("request_character_lobby_update")
	else:
		send_p2p_packet({}, MessageType.MESSAGE_TYPE_CHARACTER_SELECTED, game_lobby_owner_id)


func send_character_selection_completed(some_player_has_weapon_slots : bool, currently_focused_characters : Array) -> void:
	if not is_host():
		return

	var _err = Steam.setLobbyData(game_lobby_id, "lobby_status", "CLOSED")
	var data = {
		"HAS_WEAPON_SLOTS" : some_player_has_weapon_slots,
		"SELECTED_CHARACTERS": currently_focused_characters,
	}

	send_p2p_packet(data, MessageType.MESSAGE_TYPE_CHARACTER_SELECTION_COMPLETED)


func _receive_character_selection_completed(data : Dictionary) -> void:
	emit_signal("character_selection_complete", data["HAS_WEAPON_SLOTS"], data["SELECTED_CHARACTERS"])


func _receive_character_select(_data : Dictionary, sender_id : int) -> void:
	if sender_id == -1 or sender_id == steam_id or sender_id == game_lobby_owner_id:
		print("WARNING - received character select for player ", sender_id)
		return

	var player_index = get_lobby_index_for_player(sender_id)
	if player_index == -1:
		return

	emit_signal("player_selected_character", player_index)
	emit_signal("request_character_lobby_update")


func send_character_lobby_update(currently_focused_characters : Array, has_player_selected: Array) -> void:
	var data = {
		"SELECTED_CHARACTERS": currently_focused_characters,
		"SELECTIONS_CONFIRMED": has_player_selected,
	}

	send_p2p_packet(data, MessageType.MESSAGE_TYPE_CHARACTER_LOBBY_UPDATE)


func _receive_character_lobby_update(data : Dictionary) -> void:
	if not data.has("SELECTED_CHARACTERS") or not data.has("SELECTIONS_CONFIRMED"):
		print("WARNING - received lobby player update wihtout player selections", data)
		return

	emit_signal("character_lobby_update", data["SELECTED_CHARACTERS"], data["SELECTIONS_CONFIRMED"])


# Weapon select screen functions
func weapon_focused(weapon_key : String) -> void:
	if is_host():
		_send_weapon_lobby_update()
	else:
		send_p2p_packet({"WEAPON": weapon_key}, MessageType.MESSAGE_TYPE_WEAPON_FOCUS, game_lobby_owner_id)


func _receive_weapon_focus(data : Dictionary, sender_id : int) -> void:
	if not data.has("WEAPON"):
		print("WARNING - received weapon focus for player without weapon id ", sender_id)
		return

	if sender_id == -1 or sender_id == steam_id or sender_id == game_lobby_owner_id:
		print("WARNING - received weapon focus for player ", sender_id)
		return

	var player_index = get_lobby_index_for_player(sender_id)
	if player_index == -1:
		return

	emit_signal("player_focused_weapon", player_index, data["WEAPON"])
	_send_weapon_lobby_update()


func weapon_selected() -> void:
	if is_host():
		_send_weapon_lobby_update()
	else:
		send_p2p_packet({}, MessageType.MESSAGE_TYPE_WEAPON_SELECTED, game_lobby_owner_id)


func _receive_weapon_select(_data : Dictionary, sender_id : int) -> void:
	if sender_id == -1 or sender_id == steam_id or sender_id == game_lobby_owner_id:
		print("WARNING - received character select for player ", sender_id)
		return

	var player_index = get_lobby_index_for_player(sender_id)
	if player_index == -1:
		return

	emit_signal("player_selected_weapon", player_index)


func _send_weapon_lobby_update() -> void:
	if not get_tree().current_scene.name == "WeaponSelection":
		print("WARNING - attempting to send weapon selection when no longer in the weapon select; scene actual scene: ", get_tree().current_scene.name)
		return

	var weapon_select_scene = get_tree().current_scene

	var currently_focused_weapons = []
	for panel in weapon_select_scene._get_panels():
		var selected_item = panel.item_data
		if currently_focused_weapons.size() >= lobby_members.size():
			break
		if selected_item == null:
			currently_focused_weapons.push_back("RANDOM")
		else:
			currently_focused_weapons.push_back(weapon_select_scene.weapon_item_to_string(selected_item))

	var data = {
		"SELECTED_WEAPONS": currently_focused_weapons,
		"SELECTIONS_CONFIRMED": weapon_select_scene._has_player_selected,
	}

	send_p2p_packet(data, MessageType.MESSAGE_TYPE_WEAPON_LOBBY_UPDATE)


func _receive_weapon_lobby_update(data : Dictionary) -> void:
	if not data.has("SELECTED_WEAPONS") or not data.has("SELECTIONS_CONFIRMED"):
		print("WARNING - received lobby player update wihtout player selections", data)
		return

	emit_signal("weapon_lobby_update", data["SELECTED_WEAPONS"], data["SELECTIONS_CONFIRMED"])


# Difficulty Selection functions, there are fewer of these since clients don't make choices.
func send_difficulty_lobby_update() -> void:
	if not get_tree().current_scene.name == "DifficultySelection":
		print("WARNING - attempting to send difficulty selection when no longer in the scene, actual scene: ", get_tree().current_scene.name)
		return



func send_weapon_selection_completed(selected_weapons : Array) -> void:
	if not is_host():
		return

	var data = {
		"SELECTED_WEAPONS" : selected_weapons,
	}

	send_p2p_packet(data, MessageType.MESSAGE_TYPE_WEAPON_SELECTION_COMPLETED)


func _receive_weapon_selection_completed(data : Dictionary) -> void:
	emit_signal("weapon_selection_completed", data["SELECTED_WEAPONS"])


func difficulty_focused() -> void:
	var difficulty_selection_scene = get_tree().current_scene
	var focused_difficulty : int = difficulty_selection_scene._get_panels()[0].item_data.value

	var data = {
		"FOCUSED_DIFFICULTY": focused_difficulty,
	}

	send_p2p_packet(data, MessageType.MESSAGE_TYPE_DIFFICULTY_FOCUSED)


func _receive_difficutly_focus_update(data : Dictionary) -> void:
	if not data.has("FOCUSED_DIFFICULTY"):
		print("WARNING - received lobby player update wihtout difficulty focus; data:", data)
		return

	if not get_tree().current_scene.name == "DifficultySelection":
		print("WARNING - Received difficulty focus update when not in the current scene, current scene:", get_tree().current_scene.name)
		return

	emit_signal("difficulty_focused", data["FOCUSED_DIFFICULTY"])


func difficulty_pressed() -> void:
	var difficulty_selection_scene = get_tree().current_scene
	var selected_difficulty : int = difficulty_selection_scene._get_panels()[0].item_data.value

	var data = {
		"SELECTED_DIFFICULTY": selected_difficulty,
	}

	send_p2p_packet(data, MessageType.MESSAGE_TYPE_DIFFICULTY_PRESSED)


func _receive_difficutly_pressed(data : Dictionary) -> void:
	if not data.has("SELECTED_DIFFICULTY"):
		print("WARNING - received lobby player update wihtout difficulty focus; data:", data)
		return

	if not get_tree().current_scene.name == "DifficultySelection":
		print("WARNING - Received difficulty focus update when not in the current scene, current scene:", get_tree().current_scene.name)
		return

	emit_signal("difficulty_selected", data["SELECTED_DIFFICULTY"])

# returns -1 if the player isn't in the lobby
func get_lobby_index_for_player(player_id : int) -> int:
	for index in lobby_members.size():
		if lobby_members[index] == player_id:
			return index

	return -1


func request_shop_update(changed_shop_player_indeces : Array = []) -> void:
	emit_signal("client_shop_requested", changed_shop_player_indeces)


func send_shop_update(shop_data : Dictionary) -> void:
	send_p2p_packet(shop_data, MessageType.MESSAGE_TYPE_SHOP_LOBBY_UPDATE)


func _receive_shop_update(data : Dictionary) -> void:
	emit_signal("shop_lobby_update", data)


func shop_item_focused(shop_item_string : String, force_focus_for_players : Array = []) -> void:
	if is_host():
		request_shop_update(force_focus_for_players)
	else:
		var data = {
			"FOCUSED_ITEM": shop_item_string,
		}

		send_p2p_packet(data, MessageType.MESSAGE_TYPE_SHOP_ITEM_FOCUS, game_lobby_owner_id)


func _receive_shop_item_focus(data : Dictionary, sender_id : int) -> void:
	if not is_host():
		print("WARNING - received shop item focus as non-host, ignroing; data:", data)
		return

	if not data.has("FOCUSED_ITEM"):
		print("WARNING - received shop item focus message without focused item; data:", data)
		return

	var player_index : int = get_lobby_index_for_player(sender_id)

	emit_signal("client_shop_focus_updated", data["FOCUSED_ITEM"], player_index)


func shop_go_button_pressed(current_state : bool) -> void:
	if is_host():
		request_shop_update()
	else:
		var data = {
			"CURRENT_STATE": current_state,
		}

		send_p2p_packet(data, MessageType.MESSAGE_TYPE_SHOP_GO_BUTTON_UPDATED, game_lobby_owner_id)


func _receive_shop_go_button_pressed(data : Dictionary, sender_id : int) -> void:
	if not is_host():
		print("WARNING - received shop go button press as non-host, ignroing; data:", data)
		return

	if not data.has("CURRENT_STATE"):
		print("WARNING - received shop go button press without CURRENT_STATE; data:", data)
		return

	var player_index : int = get_lobby_index_for_player(sender_id)
	emit_signal("client_shop_go_button_pressed", data["CURRENT_STATE"], player_index)


func shop_go_button_exited() -> void:
	shop_go_button_pressed(false)


func shop_buy_item(item_string : String, player_index : int) -> void:
	if is_host():
		request_shop_update([player_index])
	else:
		var data = {
			"ITEM": item_string,
		}

		send_p2p_packet(data, MessageType.MESSAGE_TYPE_SHOP_BUY_ITEM, game_lobby_owner_id)


func _receive_shop_buy_item(data : Dictionary, sender_id : int) -> void:
	if not is_host():
		print("WARNING - received shop item buy as non-host, ignroing; data:", data)
		return

	if not data.has("ITEM"):
		print("WARNING - received shop buy item without ITEM; data:", data)
		return

	var player_index : int = get_lobby_index_for_player(sender_id)
	emit_signal("client_shop_buy_item", data["ITEM"], player_index)


func shop_reroll(player_index : int) -> void:
	if is_host():
		request_shop_update([player_index])
	else:
		send_p2p_packet({}, MessageType.MESSAGE_TYPE_SHOP_REROLL, game_lobby_owner_id)


func _receive_shop_reroll(sender_id : int) -> void:
	var player_index : int = get_lobby_index_for_player(sender_id)
	if not is_host():
		print("WARNING : client received reroll from client signal ", player_index)
		return

	emit_signal("client_shop_reroll", player_index)


func shop_weapon_discard(weapon_string : String, player_index : int) -> void:
	if is_host():
		request_shop_update([player_index])
	else:
		var data = {
			"WEAPON": weapon_string,
		}

		send_p2p_packet(data, MessageType.MESSAGE_TYPE_SHOP_WEAPON_DISCARD, game_lobby_owner_id)


func _receive_shop_weapon_discard(data : Dictionary, sender_id : int) -> void:
	if not is_host():
		print("WARNING - received shop discard as non-host, ignroing; data:", data)
		return

	if not data.has("WEAPON"):
		print("WARNING - received shop discard without WEAPON; data:", data)
		return

	var player_index : int = get_lobby_index_for_player(sender_id)
	emit_signal("client_shop_discard_weapon", data["WEAPON"], player_index)


func shop_lock_item(item_string : String, wave_value : int) -> void:
	if is_host():
		request_shop_update()
	else:
		var data = {
			"ITEM": item_string,
			"WAVE_VALUE": wave_value,
		}

		send_p2p_packet(data, MessageType.MESSAGE_TYPE_SHOP_LOCK_ITEM, game_lobby_owner_id)


func _receive_shop_lock_item(data : Dictionary, sender_id : int) -> void:
	if not is_host():
		print("WARNING - received shop lock as non-host, ignroing; data:", data)
		return

	if not data.has("ITEM") or not data.has("WAVE_VALUE"):
		print("WARNING - received shop item lock without item or wave_value; data:", data)
		return

	var player_index : int = get_lobby_index_for_player(sender_id)
	emit_signal("client_shop_lock_item", data["ITEM"], data["WAVE_VALUE"], player_index)


func shop_unlock_item(item_string : String) -> void:
	if is_host():
		request_shop_update()
	else:
		var data = {
			"ITEM": item_string,
		}

		send_p2p_packet(data, MessageType.MESSAGE_TYPE_SHOP_UNLOCK_ITEM, game_lobby_owner_id)


func _receive_shop_unlock_item(data : Dictionary, sender_id : int) -> void:
	if not is_host():
		print("WARNING - received shop unlock as non-host, ignroing; data:", data)
		return

	if not data.has("ITEM"):
		print("WARNING - received shop item unlock without item; data:", data)
		return

	var player_index : int = get_lobby_index_for_player(sender_id)
	emit_signal("client_shop_unlock_item", data["ITEM"], player_index)


func shop_combine_weapon(weapon_string : String, is_upgrade : bool, player_index : int) -> void:
	if is_host():
		request_shop_update([player_index])
	else:
		var data = {
			"WEAPON": weapon_string,
			"IS_UPGRADE": is_upgrade,
		}

		send_p2p_packet(data, MessageType.MESSAGE_TYPE_SHOP_COMBINE_WEAPON, game_lobby_owner_id)


func _receive_shop_combine_weapon(data : Dictionary, sender_id : int) -> void:
	if not is_host():
		print("WARNING - received shop weapon combine as non-host, ignroing; data:", data)
		return

	if not data.has("WEAPON") or not data.has("IS_UPGRADE"):
		print("WARNING - received shop weapon combine without weapon or is_upgrade; data:", data)
		return

	var player_index : int = get_lobby_index_for_player(sender_id)
	emit_signal("client_shop_combine_weapon", data["WEAPON"], data["IS_UPGRADE"], player_index)


func send_round_start() -> void:
	send_p2p_packet({}, MessageType.MESSAGE_TYPE_HOST_ROUND_START)


func _receive_host_round_start() -> void:
	emit_signal("host_starts_round")


func shop_focus_inventory_element(inventory_item_dict : Dictionary) -> void:
	if is_host():
		request_shop_update()
	else:
		send_p2p_packet(inventory_item_dict, MessageType.MESSAGE_TYPE_SHOP_INVENTORY_ITEM_FOCUS, game_lobby_owner_id)


func _receive_shop_focus_inventory_element(data : Dictionary, sender_id : int) -> void:
	emit_signal("client_shop_focus_inventory_element", data, get_lobby_index_for_player(sender_id))


func get_my_index() -> int:
	return get_lobby_index_for_player(steam_id)


func request_close_client_shop_popup(player_index : int) -> void:
	send_p2p_packet({}, MessageType.MESSAGE_TYPE_SHOP_CLOSE_POPUP, lobby_members[player_index])


func _receive_shop_close_popup() -> void:
	emit_signal("close_popup")


func leave_shop() -> void:
	send_p2p_packet({}, MessageType.MESSAGE_TYPE_LEAVE_SHOP)


func _receive_leave_shop() -> void:
	emit_signal("receive_leave_shop")


func send_game_state(state_dict : Dictionary) -> void:
	if is_host():
		# Positional snapshot -> UNRELIABLE: a dropped/late packet is simply superseded by
		# the next one, so we avoid reliable in-order head-of-line blocking under jitter.
		send_p2p_packet(state_dict, MessageType.MESSAGE_TYPE_MAIN_STATE, -1, Steam.P2P_SEND_UNRELIABLE)


func send_game_events(events_dict : Dictionary) -> void:
	if is_host():
		# One-shot deltas (deaths/spawns/effects) -> RELIABLE so none are ever lost.
		send_p2p_packet(events_dict, MessageType.MESSAGE_TYPE_MAIN_STATE_EVENTS)


func _receive_game_state(state_dict : Dictionary) -> void:
	if is_host():
		print("ERR - HOST SHOULD NOT BE GETTING STATE UPDATES")
		return

	emit_signal("state_update", state_dict)


func _receive_game_events(events_dict : Dictionary) -> void:
	if is_host():
		return
	emit_signal("state_events", events_dict)


func send_client_position(client_position_dict : Dictionary) -> void:
	send_p2p_packet(client_position_dict, MessageType.MESSAGE_TYPE_CLIENT_POSITION)


func _receive_client_position(data : Dictionary, sender_id : int) -> void:
	emit_signal("client_position", data, get_lobby_index_for_player(sender_id))


func send_client_menu_focus(client_menu_dict : Dictionary) -> void:
	send_p2p_packet(client_menu_dict, MessageType.MESSAGE_TYPE_CLIENT_FOCUS_MAIN_SCENE)


func _receive_client_menu_focus(data : Dictionary, sender_id: int) -> void:
	emit_signal("client_menu_focus", data, get_lobby_index_for_player(sender_id))


func send_main_scene_client_reroll_button_ressed() -> void:
	send_p2p_packet({}, MessageType.MESSAGE_TYPE_MAIN_SCENE_REROLL_BUTTON_PRESSED)


func _receive_main_scene_client_reroll_button_pressed(sender_id : int) -> void:
	emit_signal("client_main_scene_reroll_button_pressed", get_lobby_index_for_player(sender_id))


func send_main_scene_client_choose_upgrade_pressed(upgrade_data_dict : Dictionary) -> void:
	send_p2p_packet(upgrade_data_dict, MessageType.MESSAGE_TYPE_MAIN_SCENE_CHOOSE_UPGRADE_PRESSED)


func _receive_main_scene_client_choose_upgrade_pressed(upgrade_data_dict : Dictionary, sender_id : int) -> void:
	emit_signal("client_main_scene_choose_upgrade_pressed", upgrade_data_dict, get_lobby_index_for_player(sender_id))


func send_main_scene_client_take_button_pressed() -> void:
	send_p2p_packet({}, MessageType.MESSAGE_TYPE_MAIN_SCENE_TAKE_BUTTON_PRESSED)


func _receive_main_scene_client_take_button_pressed(sender_id : int) -> void:
	emit_signal("client_main_scene_take_button_pressed", get_lobby_index_for_player(sender_id))


func send_main_scene_client_discard_button_pressed() -> void:
	send_p2p_packet({}, MessageType.MESSAGE_TYPE_MAIN_SCENE_DISCARD_BUTTON_PRESSED)


func _receive_main_scene_client_discard_button_pressed(sender_id : int) -> void:
	emit_signal("client_main_scene_discard_button_pressed", get_lobby_index_for_player(sender_id))


func send_host_entered_shop() -> void:
	send_p2p_packet({}, MessageType.MESSAGE_TYPE_HOST_ENTERED_SHOP)


func _receive_host_entered_shop() -> void:
	emit_signal("host_entered_shop")
