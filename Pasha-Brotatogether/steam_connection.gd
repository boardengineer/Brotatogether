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

	# Client -> host (reliable): re-request enemy spawn statics for ids the client keeps
	# receiving positional rows for but cannot instance (the BTMISS backstop; see
	# extensions/main.gd _missing_statics / _on_enemy_statics_requested).
	MESSAGE_TYPE_ENEMY_STATICS_REQUEST,

	# Host -> clients (reliable): the run is over (every player died, or the last wave
	# was cleared). Sent from Main.clean_up_room the moment the host decides and BEFORE
	# the host leaves the lobby, so clients reach the end-run screen instead of being
	# dumped on the multiplayer menu with "Host left the lobby".
	MESSAGE_TYPE_RUN_ENDED,
	# Host -> one client: leave this lobby (kick / refused join). {REASON}
	MESSAGE_TYPE_KICKED,
}

var global_chat_lobby_id : int = -1

# Client: set by _receive_run_ended so the host's expected lobby-leave right after it is
# not mistaken for a mid-run disconnect (see _on_lobby_chat_update). Reset on every join.
var run_ended_by_host : bool = false
var steam_id : int

var game_lobby_id : int = -1
var lobby_members : Array = []
var lobby_member_names : Array = []

# When true, a game lobby we create is tagged friends_only so the lobby list only shows it to the
# host's Steam friends (see _on_lobby_match_list). Carries the create-time toggle to _on_lobby_created.
var host_friends_only : bool = false
# --- Lobby roster (host-authoritative) --------------------------------------------------
# Slot order = player index; slot 0 is always the host. The host publishes the roster in the
# Steam lobby data key "bt_slots" (comma-separated steam ids) and every client rebuilds
# lobby_members / lobby_member_names from it on lobby_data_update, so all machines agree on
# indexes even when Steam's own member enumeration order differs. During character selection
# a leaver's slot is compacted away; once the run is set up (lobby CLOSED) indexes must stay
# stable, so the slot stays and the index is listed in "bt_left" instead.
const MAX_SLOTS := 4
const ROSTER_KEY := "bt_slots"
const LEFT_KEY := "bt_left"
const LOCKED_KEY := "bt_locked"
const OPEN_KEY := "bt_open"          # open (unlocked, unoccupied) slot count, for the browser
const LEAVE_STATES := 2 | 4 | 8 | 16  # CHAT_MEMBER_STATE_CHANGE LEFT | DISCONNECTED | KICKED | BANNED
var locked_slots : Array = [false, false, false, false]   # host: closed slots (index 0 never)
var left_players : Dictionary = {}    # player_index -> true for members who left mid-run
var _kicked_ids : Dictionary = {}     # host: steam ids ejected from this lobby (re-ejected on rejoin)
var lobby_slot_info : Dictionary = {} # browser: lobby_id -> {"occupied": n, "capacity": n} from the last search
var debug_force_stranger : bool = false   # --bt-force-stranger (host): treat every joiner as a non-friend
var _pending_friend_lobbies : Dictionary = {}   # lobby ids we asked Steam to fetch data for (friend scan)
var _search_seen : Dictionary = {}              # lobby ids already emitted for the current search

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

# --- BTLAT: client-side MAIN_STATE latency profiling (--bt-latprof) -----------------------
# Quantifies the two receive-side latencies:
#   L1 steady-state: per-snapshot decode (gunzip+bytes2var) and apply (_state_update) cost.
#   L2 backlog:      when a frame drains >1 queued snapshot (after a client stall), the
#                    recovery frame pays decode+apply for every queued packet even though
#                    only the newest matters -- logged per event with the wasted applies.
# Inter-arrival gap is client-clock; "jitter" subtracts the host's send spacing (SENT_AT_MS
# delta), which is clock-offset-free because both terms are deltas on their own clocks.
# Zero overhead unless --bt-latprof is on the command line. Output: BTLAT lines on stdout.
var _latprof_enabled : bool = false
var _lat_decode_samples := []            # us per MAIN_STATE packet, current window
var _lat_apply_samples := []             # us per MAIN_STATE packet (incl. seq-skipped ~0s)
var _lat_gap_samples := []               # ms between read passes that carried MAIN_STATE
var _lat_jitter_samples := []            # ms: arrival gap minus host send gap
var _lat_applied : int = 0               # packets fully applied this window
var _lat_packets : int = 0               # MAIN_STATE packets seen this window
var _lat_max_drain : int = 0             # most MAIN_STATE packets in one read pass
var _lat_backlog_events : int = 0        # read passes with >1 MAIN_STATE packet
var _lat_wasted_applies : int = 0        # superseded-but-applied packets (backlog n-1 each)
var _lat_prev_arrival_ms : int = -1      # client clock, last pass that carried MAIN_STATE
var _lat_prev_sent_ms : int = -1         # host SENT_AT_MS of newest packet in that pass
var _lat_max_seen_seq : int = -1         # mirrors the apply guard: counts truly-applied packets
var _lat_flush_ms : int = 0              # client clock of last summary print
# v2 (late-wave density): compressed snapshot bytes, reliable-fallback detection (a packet
# over UNRELIABLE_MAX_BYTES can only have been sent RELIABLE -- same threshold the host
# uses), gap split by delivery mode, and enemies+bosses per snapshot (row count / 9).
var _lat_bytes_samples := []             # compressed MAIN_STATE packet bytes, current window
var _lat_rel_count : int = 0             # packets that rode the RELIABLE fallback this window
var _lat_gap_rel := []                   # arrival gaps (ms) where the newest packet was reliable
var _lat_gap_unrel := []                 # arrival gaps (ms) where it was unreliable
var _lat_max_enemies : int = 0           # max enemies+bosses in one snapshot this window
const LAT_FLUSH_INTERVAL_MS : int = 5000


static func _lat_pct(sorted_arr : Array, p : float) -> int:
	if sorted_arr.empty():
		return 0
	var idx = int(clamp(ceil(p * sorted_arr.size()) - 1, 0, sorted_arr.size() - 1))
	return int(sorted_arr[idx])


func _lat_flush_summary(now_ms : int) -> void:
	_lat_decode_samples.sort()
	_lat_apply_samples.sort()
	_lat_gap_samples.sort()
	_lat_jitter_samples.sort()
	_lat_bytes_samples.sort()
	_lat_gap_rel.sort()
	_lat_gap_unrel.sort()
	print("BTLAT sum win_ms=%d n=%d applied=%d p50_dec_us=%d p95_dec_us=%d max_dec_us=%d p50_app_us=%d p95_app_us=%d max_app_us=%d maxdrain=%d backlogs=%d wasted=%d p50_gap_ms=%d p95_gap_ms=%d max_gap_ms=%d p95_jit_ms=%d enemies_max=%d rel_n=%d p50_bytes=%d p95_bytes=%d max_bytes=%d p95_gap_rel_ms=%d p95_gap_unrel_ms=%d" % [
		now_ms - _lat_flush_ms, _lat_packets, _lat_applied,
		_lat_pct(_lat_decode_samples, 0.5), _lat_pct(_lat_decode_samples, 0.95), _lat_pct(_lat_decode_samples, 1.0),
		_lat_pct(_lat_apply_samples, 0.5), _lat_pct(_lat_apply_samples, 0.95), _lat_pct(_lat_apply_samples, 1.0),
		_lat_max_drain, _lat_backlog_events, _lat_wasted_applies,
		_lat_pct(_lat_gap_samples, 0.5), _lat_pct(_lat_gap_samples, 0.95), _lat_pct(_lat_gap_samples, 1.0),
		_lat_pct(_lat_jitter_samples, 0.95),
		_lat_max_enemies, _lat_rel_count,
		_lat_pct(_lat_bytes_samples, 0.5), _lat_pct(_lat_bytes_samples, 0.95), _lat_pct(_lat_bytes_samples, 1.0),
		_lat_pct(_lat_gap_rel, 0.95), _lat_pct(_lat_gap_unrel, 0.95)])
	_lat_decode_samples.clear()
	_lat_apply_samples.clear()
	_lat_gap_samples.clear()
	_lat_jitter_samples.clear()
	_lat_bytes_samples.clear()
	_lat_gap_rel.clear()
	_lat_gap_unrel.clear()
	_lat_applied = 0
	_lat_packets = 0
	_lat_max_drain = 0
	_lat_backlog_events = 0
	_lat_wasted_applies = 0
	_lat_rel_count = 0
	_lat_max_enemies = 0
	_lat_flush_ms = now_ms
# --- end BTLAT ---------------------------------------------------------------------------

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
# Slots compacted away during character selection (indices as they were before removal).
signal lobby_roster_changed(removed_indices)
# A member left after the run was set up; its slot stays, flagged in left_players.
signal player_left_run(player_index)
# Roster / lock state changed (labels, slot controls, browser counts).
signal lobby_slots_updated()

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

# Host side: a client asked for enemy spawn statics it never received (BTMISS backstop).
signal enemy_statics_requested(ids)

# Client-side: the host declared the run over (won=true: last wave cleared; false: every
# player died). delay = the host's own end-wave timer, so both screens flip together.
signal host_run_ended(won, delay)

signal state_events(events_dict)

signal client_position(client_position_dict, player_index)

signal client_menu_focus(client_menu_focus_dict, player_index)

signal client_main_scene_reroll_button_pressed(player_index)

signal client_main_scene_choose_upgrade_pressed(upgrade_data_dict, player_index)

signal client_main_scene_take_button_pressed(player_index)

signal client_main_scene_discard_button_pressed(player_index)

signal host_entered_shop()

func _ready():
	_latprof_enabled = "--bt-latprof" in OS.get_cmdline_args()
	if _latprof_enabled:
		print("BTLAT armed (client-side MAIN_STATE latency profiling)")
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
	_err = Steam.connect("lobby_data_update", self, "_on_lobby_data_update")
	_err = Steam.connect("join_requested", self, "_on_join_requested")

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
		var lobby_friends_only : bool = false
		var lobby_owner_id : String = ""
		var slots_csv : String = ""
		var open_str : String = ""

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
			elif key == "friends_only":
				lobby_friends_only = (value == "1")
			elif key == "owner_id":
				lobby_owner_id = value
			elif key == ROSTER_KEY:
				slots_csv = value
			elif key == OPEN_KEY:
				open_str = value

		if is_game_lobby:
			# A friends_only lobby is only listed for the host's friends (and the host).
			if lobby_friends_only and not _is_self_or_friend(lobby_owner_id):
				continue
			if _search_seen.has(lobby_id):
				continue   # already listed via the friend scan
			_search_seen[lobby_id] = true
			# Slot counts for the browser: seated players / (seated + open, i.e. unlocked empty).
			var occupied : int = slots_csv.split(",").size() if slots_csv != "" else Steam.getNumLobbyMembers(lobby_id)
			var open_n : int = int(open_str) if open_str != "" else int(max(0, MAX_SLOTS - occupied))
			lobby_slot_info[lobby_id] = {"occupied": occupied, "capacity": occupied + open_n}
			emit_signal("game_lobby_found", lobby_id, game_lobby_name)

	if found_global_chat_lobby:
		if min_chat_lobby_id != global_chat_lobby_id:
			Steam.joinLobby(min_chat_lobby_id)
	else:
		if global_chat_lobby_id == -1 and not is_creating_global_chat_lobby:
			is_creating_global_chat_lobby = true
			Steam.createLobby(Steam.LOBBY_TYPE_INVISIBLE, 250)


func leave_game_lobby() -> void:
	_pending_state_events.clear()   # never leak buffered events into a future run
	Utils.remote_player_stats.clear()   # host-authoritative stat overrides die with the run
	left_players.clear()
	_kicked_ids.clear()
	for i in MAX_SLOTS:
		locked_slots[i] = false
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
			# Friends-only visibility: the lobby stays discoverable, but the lobby list only shows
			# it to the host's friends (owner_id lets a searcher check the friend relationship).
			_err = Steam.setLobbyData(created_lobby_id, "friends_only", "1" if host_friends_only else "0")
			_err = Steam.setLobbyData(created_lobby_id, "owner_id", str(Steam.getSteamID()))
			# Fresh roster: just me in slot 0. Published before anyone can join.
			lobby_members = [steam_id]
			lobby_member_names = [Steam.getFriendPersonaName(steam_id)]
			left_players.clear()
			_kicked_ids.clear()
			_publish_roster()
			var _j = Steam.setLobbyJoinable(created_lobby_id, true)
			# Stamp our version/DLC/mods so joining clients can refuse an incompatible game.
			_stamp_compat_lobby_data(created_lobby_id)


func _request_global_chat_search() -> void:
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("lobby_type", GLOBAL_CHAT_TYPE, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()


func request_lobby_search() -> void:
	_search_seen.clear()
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("lobby_type", GAME_LOBBY_TYPE, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter("lobby_status", "OPEN", Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()
	# Friends-only lobbies never come back from requestLobbyList: find them through friends'
	# rich presence (getFriendGamePlayed carries the lobby id) and fetch their data asynchronously.
	_scan_friend_lobbies()


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
					run_ended_by_host = false
					game_lobby_owner_id = Steam.getLobbyOwner(lobby_id)

					# Joining a game that already started (invite / stale browser entry): bounce.
					if game_lobby_owner_id != steam_id and Steam.getLobbyData(lobby_id, "lobby_status") != "OPEN":
						pending_system_messages.push_back("Cannot join lobby -- the game is already in progress")
						Steam.leaveLobby(lobby_id)
						game_lobby_id = -1
						$"/root/BrotogetherOptions".joining_multiplayer_lobby = false
						var _e2 = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_menu.tscn")
						return
					# Roster comes from the host's published slot order, not Steam's enumeration.
					if not _apply_roster_string(Steam.getLobbyData(lobby_id, ROSTER_KEY)):
						lobby_members.clear()
						lobby_member_names.clear()
						for member_index in Steam.getNumLobbyMembers(lobby_id):
							var member_id = Steam.getLobbyMemberByIndex(lobby_id, member_index)
							lobby_members.push_back(member_id)
							lobby_member_names.push_back(Steam.getFriendPersonaName(member_id))
					_apply_left_string(Steam.getLobbyData(lobby_id, LEFT_KEY))
					_apply_locked_string(Steam.getLobbyData(lobby_id, LOCKED_KEY))
					# The host appends us to the roster when it sees our ENTERED; until that
					# publish lands, take the slot it will give us (end of the list).
					if not lobby_members.has(steam_id):
						lobby_members.push_back(steam_id)
						lobby_member_names.push_back(Steam.getFriendPersonaName(steam_id))

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
			print("%s has joined the lobby." % changer_name)
			# Only the host seats (or refuses) a newcomer; clients learn the new roster from
			# the host's lobby data instead of guessing the order.
			if is_host():
				_host_admit(change_id, changer_name)

	# Left, disconnected (timeout), kicked and banned all vacate the member.
	elif (chat_state & LEAVE_STATES) != 0:
		# Only treat an owner-left as "host left" for OUR game lobby. Without the lobby_id guard a
		# LEFT in the global chat lobby (or a lobby we bailed out of, e.g. an incompatible join)
		# whose leaver id matched game_lobby_owner_id would spuriously kick us back to the menu.
		if lobby_id == game_lobby_id and game_lobby_id != -1 and change_id == game_lobby_owner_id:
			if run_ended_by_host:
				# Expected: the host leaves right after send_run_ended and Main is already
				# on its way to the end-run screen. Just drop the lobby, no menu bounce.
				leave_game_lobby()
			else:
				pending_system_messages.push_back("Host left the lobby")
				leave_game_lobby()
				var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_menu.tscn")
		elif lobby_id == game_lobby_id and game_lobby_id != -1 and is_host():
			_host_member_left(change_id, changer_name)
		print("%s has left the lobby (state %d)." % [changer_name, chat_state])

	else:
		print("%s did... something (state %d)." % [changer_name, chat_state])


# --- Roster helpers ----------------------------------------------------------------------

func _roster_open_slot_count() -> int:
	var open := 0
	for i in MAX_SLOTS:
		if i >= lobby_members.size() and not locked_slots[i]:
			open += 1
	return open


# Steam refuses joins beyond the member limit: occupied + open (unlocked, empty) slots.
func _member_limit() -> int:
	return int(max(1, lobby_members.size() + _roster_open_slot_count()))


# Host: push roster / left / locked / open-count into the lobby data and size the member limit.
func _publish_roster() -> void:
	if not is_host() or game_lobby_id <= 0:
		return
	var ids := []
	for id in lobby_members:
		ids.push_back(str(id))
	var left := []
	for idx in left_players.keys():
		left.push_back(str(idx))
	var locked := ""
	for i in MAX_SLOTS:
		locked += "1" if locked_slots[i] else "0"
	var _e = Steam.setLobbyData(game_lobby_id, ROSTER_KEY, PoolStringArray(ids).join(","))
	_e = Steam.setLobbyData(game_lobby_id, LEFT_KEY, PoolStringArray(left).join(","))
	_e = Steam.setLobbyData(game_lobby_id, LOCKED_KEY, locked)
	_e = Steam.setLobbyData(game_lobby_id, OPEN_KEY, str(_roster_open_slot_count()))
	_e = Steam.setLobbyMemberLimit(game_lobby_id, _member_limit())
	emit_signal("lobby_slots_updated")


# Rebuild lobby_members / lobby_member_names from "id,id,...". False when the key is absent.
func _apply_roster_string(s) -> bool:
	if s == null or str(s) == "":
		return false
	var ids := []
	for part in str(s).split(","):
		var id := int(part)
		if id != 0:
			ids.push_back(id)
	if ids.empty():
		return false
	lobby_members.clear()
	lobby_member_names.clear()
	for id in ids:
		lobby_members.push_back(id)
		lobby_member_names.push_back(Steam.getFriendPersonaName(id))
	return true


func _apply_left_string(s) -> void:
	left_players.clear()
	if s == null or str(s) == "":
		return
	for part in str(s).split(","):
		if part != "":
			left_players[int(part)] = true


func _apply_locked_string(s) -> void:
	var txt := str(s) if s != null else ""
	for i in MAX_SLOTS:
		locked_slots[i] = i < txt.length() and txt[i] == "1"


func _lobby_is_open() -> bool:
	return game_lobby_id > 0 and Steam.getLobbyData(game_lobby_id, "lobby_status") == "OPEN"


func _is_steam_lobby_member(member_id : int) -> bool:
	if game_lobby_id <= 0:
		return false
	for i in Steam.getNumLobbyMembers(game_lobby_id):
		if Steam.getLobbyMemberByIndex(game_lobby_id, i) == member_id:
			return true
	return false


# Locks are positional while slots are empty (the host clicks a specific slot), but seating is
# always compact (player index = roster order), so after any seat change the open-seat COUNT is
# what survives: the first `open_count` empty slots are open, the rest locked.
func _normalize_locks(open_count : int) -> void:
	var size := lobby_members.size()
	for i in MAX_SLOTS:
		if i < size:
			locked_slots[i] = false
		else:
			locked_slots[i] = (i - size) >= open_count


# Host: seat or refuse a member Steam just let in.
func _host_admit(member_id : int, member_name : String) -> void:
	if member_id == steam_id:
		return
	if lobby_members.has(member_id):
		# Same account re-entering while its old (hard-killed) session is still on the roster:
		# keep the slot, republish so the new session gets its roster, and let the selection
		# screen rebuild. The old session's late LEFT is ignored in _host_member_left.
		print("BTLOBBY re-seated %s in slot %d" % [member_name, get_lobby_index_for_player(member_id)])
		_publish_roster()
		emit_signal("lobby_players_updated")
		return
	var reason := ""
	if _kicked_ids.has(member_id):
		reason = "You were removed from this lobby"
	elif not _lobby_is_open():
		reason = "The game is already in progress"
	elif host_friends_only and not _is_friend(member_id):
		reason = "This lobby is friends only"
	elif _roster_open_slot_count() <= 0:
		reason = "The lobby is full"
	if reason != "":
		print("BTLOBBY refusing %s: %s" % [member_name, reason])
		_kick(member_id, reason)
		return
	var open_before := _roster_open_slot_count()
	lobby_members.push_back(member_id)
	lobby_member_names.push_back(member_name)
	_normalize_locks(open_before - 1)   # the newcomer took one open seat
	print("BTLOBBY seated %s in slot %d" % [member_name, lobby_members.size() - 1])
	_publish_roster()
	emit_signal("lobby_players_updated")


# Host: a member is gone. During character selection the slot is compacted away; once the run
# is set up (lobby CLOSED) indexes must stay stable, so the slot stays and is flagged.
func _host_member_left(member_id : int, member_name : String) -> void:
	var idx := get_lobby_index_for_player(member_id)
	if idx <= 0:
		return
	# A hard-killed client that rejoined before Steam noticed produces ENTERED (new session)
	# followed by a late LEFT (old session). Steam still lists the account as a member then,
	# so that LEFT is stale: acting on it wiped the fresh seat (RC1 a3, 2026-09-13).
	if _is_steam_lobby_member(member_id):
		print("BTLOBBY ignoring stale LEFT for %s (still a lobby member)" % member_name)
		return
	if _lobby_is_open():
		var open_before := _roster_open_slot_count()
		lobby_members.remove(idx)
		lobby_member_names.remove(idx)
		_normalize_locks(open_before + 1)   # the vacated seat is open again
		_publish_roster()
		print("BTLOBBY %s left slot %d (compacted)" % [member_name, idx])
		emit_signal("lobby_roster_changed", [idx])
	else:
		left_players[idx] = true
		_publish_roster()
		print("BTLOBBY %s left slot %d mid-run" % [member_name, idx])
		emit_signal("player_left_run", idx)


# Host: eject a member. Steam lobbies have no kick, so the client is told to leave and its id
# is refused for the rest of this lobby's life.
func _kick(member_id : int, reason : String) -> void:
	_kicked_ids[member_id] = true
	send_p2p_packet({"REASON": reason}, MessageType.MESSAGE_TYPE_KICKED, member_id)
	var idx := get_lobby_index_for_player(member_id)
	if idx > 0:
		var open_before := _roster_open_slot_count()
		lobby_members.remove(idx)
		lobby_member_names.remove(idx)
		_normalize_locks(open_before + 1)
		_publish_roster()
		emit_signal("lobby_roster_changed", [idx])


# UI entry point (host): kick the player in a slot.
func kick_player(player_index : int) -> void:
	if not is_host() or player_index <= 0 or player_index >= lobby_members.size():
		return
	_kick(lobby_members[player_index], "You were removed from the lobby by the host")


# UI entry point (host): close / open an empty slot. Occupied slots cannot be locked.
func set_slot_locked(slot : int, locked : bool) -> void:
	if not is_host() or slot <= 0 or slot >= MAX_SLOTS or slot < lobby_members.size():
		return
	locked_slots[slot] = locked
	_publish_roster()


func _receive_kicked(data : Dictionary, sender_id : int) -> void:
	if is_host() or sender_id != game_lobby_owner_id:
		return
	_kicked_out(str(data.get("REASON", "Removed from the lobby")))


func _kicked_out(reason : String) -> void:
	pending_system_messages.push_back(reason)
	leave_game_lobby()
	$"/root/BrotogetherOptions".joining_multiplayer_lobby = false
	var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_menu.tscn")


# Clients: the host changed lobby data -- re-derive roster / left / locked and react.
func _on_lobby_data_update(_success : int, lobby_id : int, member_id : int) -> void:
	# Friend scan: the data we asked for arrived; list the lobby if it is one of ours and open.
	if _pending_friend_lobbies.has(lobby_id) and member_id == lobby_id:
		_pending_friend_lobbies.erase(lobby_id)
		_consider_friend_lobby(lobby_id)
		return
	if lobby_id != game_lobby_id or game_lobby_id <= 0 or member_id != lobby_id or is_host():
		return
	var before := lobby_members.duplicate()
	var before_left := left_players.duplicate()
	if not _apply_roster_string(Steam.getLobbyData(lobby_id, ROSTER_KEY)):
		return
	_apply_left_string(Steam.getLobbyData(lobby_id, LEFT_KEY))
	_apply_locked_string(Steam.getLobbyData(lobby_id, LOCKED_KEY))
	emit_signal("lobby_slots_updated")
	if not lobby_members.has(steam_id):
		_kicked_out("Removed from the lobby")
		return
	var removed := []
	for i in before.size():
		if not lobby_members.has(before[i]):
			removed.push_back(i)
	if removed.size() > 0:
		emit_signal("lobby_roster_changed", removed)
	elif lobby_members.size() > before.size():
		emit_signal("lobby_players_updated")
	for idx in left_players.keys():
		if not before_left.has(idx):
			emit_signal("player_left_run", idx)


# EFriendRelationship k_EFriendRelationshipFriend == 3. --bt-force-stranger makes everyone a
# stranger so the host-side refusal can be exercised between two accounts that ARE friends.
func _is_friend(member_id : int) -> bool:
	if debug_force_stranger:
		return false
	return Steam.getFriendRelationship(member_id) == 3


# Browser: ask Steam for the lobby data of every friend currently sitting in a lobby of this app.
func _scan_friend_lobbies() -> void:
	var my_app : int = Steam.getAppID()
	for i in Steam.getFriendCount(Steam.FRIEND_FLAG_IMMEDIATE):
		var friend_id : int = Steam.getFriendByIndex(i, Steam.FRIEND_FLAG_IMMEDIATE)
		var played = Steam.getFriendGamePlayed(friend_id)
		if typeof(played) != TYPE_DICTIONARY:
			continue
		var lobby_id : int = int(played.get("lobby", 0))
		if lobby_id == 0 or int(played.get("id", 0)) != my_app or lobby_id == game_lobby_id:
			continue
		if _search_seen.has(lobby_id) or _pending_friend_lobbies.has(lobby_id):
			continue
		_pending_friend_lobbies[lobby_id] = true
		var _r = Steam.requestLobbyData(lobby_id)


# Browser: a friend's lobby data arrived -- list it like a public search hit if it qualifies.
func _consider_friend_lobby(lobby_id : int) -> void:
	if _search_seen.has(lobby_id):
		return
	if str(Steam.getLobbyData(lobby_id, "lobby_type")) != GAME_LOBBY_TYPE:
		return
	if str(Steam.getLobbyData(lobby_id, "lobby_status")) != "OPEN":
		return
	var slots_csv := str(Steam.getLobbyData(lobby_id, ROSTER_KEY))
	var open_str := str(Steam.getLobbyData(lobby_id, OPEN_KEY))
	var occupied : int = slots_csv.split(",").size() if slots_csv != "" else Steam.getNumLobbyMembers(lobby_id)
	var open_n : int = int(open_str) if open_str != "" else int(max(0, MAX_SLOTS - occupied))
	if open_n <= 0:
		return
	_search_seen[lobby_id] = true
	lobby_slot_info[lobby_id] = {"occupied": occupied, "capacity": occupied + open_n}
	emit_signal("game_lobby_found", lobby_id, str(Steam.getLobbyData(lobby_id, "lobby_name")))


# UI entry point (host): Steam overlay invite dialog for the current game lobby.
func invite_friends() -> void:
	if game_lobby_id > 0:
		Steam.activateGameOverlayInviteDialog(game_lobby_id)


# Steam overlay "Join game" / accepted invite while we are not in a game lobby.
func _on_join_requested(lobby_id : int, _friend_id : int) -> void:
	if game_lobby_id > 0:
		return
	attempt_join_game_lobby(lobby_id)


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


func create_new_game_lobby(friends_only : bool = false) -> void:
	host_friends_only = friends_only
	# Friends-only is enforced by the MOD, not by the Steam lobby type: the lobby stays PUBLIC so
	# the in-game browser can list it, the browser hides it from non-friends (friends_only lobby
	# data + owner_id), and _host_admit refuses any non-friend who joins anyway. A Steam
	# LOBBY_TYPE_FRIENDS_ONLY lobby would only be discoverable through friend presence
	# (getFriendGamePlayed), which proved unreliable in testing (2026-09-11); invites and the
	# overlay "join game" path (join_requested) work with a public lobby too.
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 4)


# True if `owner_id_str` (a Steam id) is the local user or one of their Steam friends. Used to
# hide friends_only lobbies from strangers in the lobby list.
func _is_self_or_friend(owner_id_str : String) -> bool:
	if owner_id_str == "":
		return false
	var owner_id := int(owner_id_str)
	if owner_id == 0:
		return false
	if owner_id == Steam.getSteamID():
		return true
	# EFriendRelationship: k_EFriendRelationshipFriend == 3 (stable Steamworks value).
	return Steam.getFriendRelationship(owner_id) == 3


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
		for member_index in lobby_members.size():
			var lobby_member_id = lobby_members[member_index]
			# Departed members keep their slot (stable indexes) but get no more traffic.
			if lobby_member_id != steam_id and not left_players.has(member_index):
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
	# BTLAT pass-local accounting: one "pass" = one full drain of all channels this frame.
	var lat_n : int = 0             # MAIN_STATE packets handled this pass
	var lat_pass_us : int = 0       # decode+apply us spent on them this pass
	var lat_first_seq : int = -1
	var lat_last_seq : int = -1
	var lat_newest_sent_ms : int = -1
	var lat_pass_rel : bool = false # newest MAIN_STATE packet this pass rode the reliable fallback
	for channel in MessageType.values():
		var packet_size: int = Steam.getAvailableP2PPacketSize(channel)

		while packet_size > 0:
			var packet : Dictionary = Steam.readP2PPacket(packet_size, channel)

			if packet == null or packet.empty():
				packet_size = 0
				continue

			var sender_id : int = packet["remote_steam_id"]
			# Only the host we joined or a seated roster member may drive our state.
			if sender_id != game_lobby_owner_id and get_lobby_index_for_player(sender_id) == -1:
				packet_size = Steam.getAvailableP2PPacketSize(channel)
				continue
			var lat_on : bool = _latprof_enabled and channel == MessageType.MESSAGE_TYPE_MAIN_STATE
			var lat_t0 : int = Time.get_ticks_usec() if lat_on else 0
			var data : Dictionary = bytes2var(packet["data"].decompress_dynamic(-1, File.COMPRESSION_GZIP))
			if lat_on:
				var lat_dec_us : int = Time.get_ticks_usec() - lat_t0
				_lat_decode_samples.push_back(lat_dec_us)
				lat_pass_us += lat_dec_us

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
				if _latprof_enabled:
					# Compressed size + delivery mode: only an over-MTU packet can have been
					# sent RELIABLE (host falls back above UNRELIABLE_MAX_BYTES), so the size
					# the client read classifies the path exactly with no protocol change.
					_lat_bytes_samples.push_back(packet_size)
					lat_pass_rel = packet_size > UNRELIABLE_MAX_BYTES
					if lat_pass_rel:
						_lat_rel_count += 1
					# Density: enemies + bosses ride as flat 9-int rows (ENEMY_ROW_STRIDE).
					var lat_ec : int = 0
					# Packed bytes since 2026-09-10 (main.gd ENEMY_ROW_BYTES=16); ints (9/row) before.
					var lat_rows = data.get("ENEMIES", null)
					if lat_rows != null:
						lat_ec = int(lat_rows.size() / (16 if lat_rows is PoolByteArray else 9))
					var lat_brows = data.get("BOSSES", null)
					if lat_brows != null:
						lat_ec += int(lat_brows.size() / (16 if lat_brows is PoolByteArray else 9))
					if lat_ec > _lat_max_enemies:
						_lat_max_enemies = lat_ec
					var lat_seq : int = int(data.get("SEQ", 0))
					var lat_app_t0 : int = Time.get_ticks_usec()
					_receive_game_state(data)
					var lat_app_us : int = Time.get_ticks_usec() - lat_app_t0
					_lat_apply_samples.push_back(lat_app_us)
					lat_pass_us += lat_app_us
					lat_n += 1
					_lat_packets += 1
					if lat_seq > _lat_max_seen_seq:
						_lat_max_seen_seq = lat_seq
						_lat_applied += 1
					elif lat_seq <= 2:
						# fresh Main scene restarts SEQ at 1 each wave
						_lat_max_seen_seq = lat_seq
						_lat_applied += 1
					if lat_first_seq < 0:
						lat_first_seq = lat_seq
					lat_last_seq = lat_seq
					var lat_sent = data.get("SENT_AT_MS", -1)
					if lat_sent != null and int(lat_sent) > 0:
						lat_newest_sent_ms = int(lat_sent)
				else:
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
			elif channel == MessageType.MESSAGE_TYPE_ENEMY_STATICS_REQUEST:
				_receive_enemy_statics_request(data)
			elif channel == MessageType.MESSAGE_TYPE_RUN_ENDED:
				_receive_run_ended(data)
			elif channel == MessageType.MESSAGE_TYPE_KICKED:
				_receive_kicked(data, sender_id)

			packet_size = Steam.getAvailableP2PPacketSize(channel)

	# BTLAT pass-end: gap/jitter between MAIN_STATE-carrying passes, backlog events, summary.
	if _latprof_enabled and lat_n > 0:
		var lat_now_ms : int = Time.get_ticks_msec()
		if _lat_prev_arrival_ms >= 0:
			var lat_gap_ms : int = lat_now_ms - _lat_prev_arrival_ms
			_lat_gap_samples.push_back(lat_gap_ms)
			if lat_pass_rel:
				_lat_gap_rel.push_back(lat_gap_ms)
			else:
				_lat_gap_unrel.push_back(lat_gap_ms)
			if lat_newest_sent_ms > 0 and _lat_prev_sent_ms > 0:
				# both terms are same-clock deltas, so the host/client clock offset cancels
				_lat_jitter_samples.push_back(lat_gap_ms - (lat_newest_sent_ms - _lat_prev_sent_ms))
		_lat_prev_arrival_ms = lat_now_ms
		if lat_newest_sent_ms > 0:
			_lat_prev_sent_ms = lat_newest_sent_ms
		if lat_n > _lat_max_drain:
			_lat_max_drain = lat_n
		if lat_n > 1:
			_lat_backlog_events += 1
			_lat_wasted_applies += lat_n - 1
			print("BTLAT backlog n=%d pass_us=%d seq_first=%d seq_last=%d" % [lat_n, lat_pass_us, lat_first_seq, lat_last_seq])
		if _lat_flush_ms == 0:
			_lat_flush_ms = lat_now_ms
		elif lat_now_ms - _lat_flush_ms >= LAT_FLUSH_INTERVAL_MS:
			_lat_flush_summary(lat_now_ms)


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

	var ping_index := get_lobby_index_for_player(sender_id)
	if ping_index >= 0:
		emit_signal("client_status_received", data, ping_index)
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

	# Accept only from the host we joined or someone Steam lists in our game lobby.
	if remote_id != game_lobby_owner_id and get_lobby_index_for_player(remote_id) == -1 \
			and not _is_steam_lobby_member(remote_id):
		print("BTLOBBY ignoring P2P session request from non-member %s" % this_requester)
		return
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
	_err = Steam.setLobbyJoinable(game_lobby_id, false)   # Steam-level: no one joins a running game
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
	# Anything still queued from the PREVIOUS wave's tail is stale once a new round
	# begins -- only events arriving between now and the new Main's _ready matter.
	_pending_state_events.clear()
	# Shop-time stat overrides must never leak into combat: the client's own player
	# would read frozen shop values (speed, HP...) in its local simulation.
	Utils.remote_player_stats.clear()
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


# BTMISS backstop: the client asks the host to resend spawn statics for ids it has rows
# for but cannot instance. Reliable (default send type); host answers via send_game_events.
func request_enemy_statics(ids : Array) -> void:
	if is_host():
		return
	send_p2p_packet({"IDS": ids}, MessageType.MESSAGE_TYPE_ENEMY_STATICS_REQUEST, game_lobby_owner_id)


func _receive_enemy_statics_request(data : Dictionary) -> void:
	if not is_host():
		return
	emit_signal("enemy_statics_requested", data.get("IDS", []))


# Run over (host -> clients, reliable). See MESSAGE_TYPE_RUN_ENDED.
func send_run_ended(won : bool, delay : float) -> void:
	if is_host():
		send_p2p_packet({"WON": won, "DELAY": delay}, MessageType.MESSAGE_TYPE_RUN_ENDED)


func _receive_run_ended(data : Dictionary) -> void:
	if is_host():
		return
	run_ended_by_host = true
	emit_signal("host_run_ended", data.get("WON", false), float(data.get("DELAY", 0.5)))


func _receive_game_state(state_dict : Dictionary) -> void:
	if is_host():
		print("ERR - HOST SHOULD NOT BE GETTING STATE UPDATES")
		return

	emit_signal("state_update", state_dict)


# One-shot reliable deltas (enemy spawn statics, deaths, effects). These are sent EXACTLY
# ONCE per fact (e.g. _enemy_statics_sent), but the client's Main scene takes ~1.1s to
# instantiate at every wave start (measured: the 62-71 snapshot backlog) and only connects
# "state_events" in its _ready. An emit with no listener silently discards the payload, so
# every enemy first seen by the host during that window stayed INVISIBLE on the client all
# wave (its rows are skipped for lack of statics), and deaths lost the same way could leave
# ghosts. Buffer undeliverable events here; the client Main drains them, in order, right
# after connecting (drain_pending_state_events).
var _pending_state_events := []

func _receive_game_events(events_dict : Dictionary) -> void:
	if is_host():
		return
	if get_signal_connection_list("state_events").empty():
		_pending_state_events.push_back(events_dict)
		return
	emit_signal("state_events", events_dict)


# Called by the client Main scene right after it connects "state_events": replay every
# events packet that arrived while no listener existed (wave-start scene load), oldest
# first, so one-shot spawn statics and deaths are never lost.
func drain_pending_state_events() -> void:
	if _pending_state_events.empty():
		return
	print("BTNET replaying %d buffered state_events packet(s) queued during scene load" % _pending_state_events.size())
	var queued = _pending_state_events
	_pending_state_events = []
	for events_dict in queued:
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
