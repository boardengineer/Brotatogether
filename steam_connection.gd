extends "res://mods-unpacked/Pasha-Brotatogether/networking/connection.gd"

var lobby_id = 0
var parent
var established_p2p_connections = {}
var pending_system_messages = []

var rpcs_by_type = {}
var prev_sec = 0

func _ready():
	lobby_id = 0
	var _connect_error = Steam.connect("lobby_created", self, "_on_Lobby_Created")
	_connect_error = Steam.connect("lobby_match_list", self, "_on_Lobby_Match_List")
	_connect_error = Steam.connect("lobby_joined", self, "_on_Lobby_Joined")
	_connect_error = Steam.connect("lobby_chat_update", self, "_on_Lobby_Chat_Update")
	_connect_error = Steam.connect("p2p_session_request", self, "_on_P2P_Session_Request")

func _process(_delta):
	if lobby_id > 0:
		while read_p2p_packet():
			pass

func read_p2p_packet() -> bool:
	var packet_size = Steam.getAvailableP2PPacketSize(0)
	var sec = Time.get_time_dict_from_system()["second"]
	if sec != prev_sec:
		rpcs_by_type.clear()
		prev_sec = sec
	
	if packet_size > 0:
		var packet = Steam.readP2PPacket(packet_size, 0)
		var sender = packet["steam_id_remote"]
		var data = bytes2var(packet["data"].decompress_dynamic(-1, File.COMPRESSION_GZIP))
		var type = data.type
		
		if not rpcs_by_type.has(type):
			rpcs_by_type[type] = 0
		rpcs_by_type[type] += 1
		if rpcs_by_type[type] > 100: # Prevent packet flood
			return true
		
		if type == "start_game":
			parent.start_game(data.game_info)
		elif type == "reroll_upgrades":
			parent.receive_reroll_upgrades(sender, data.reroll_price)
		elif type == "weapon_discard":
			parent.receive_item_discard(data.weapon_id, sender)
		elif type == "send_combine_item":
			parent.receive_item_combine(data.weapon_data_id, data.is_upgrade, data.player_id)
		elif type == "discard_item_box":
			parent.receive_discard_item_box(sender, data.item_id)
		elif type == "send_take_item_box":
			parent.receive_item_box_take(data.item_id, data.player_id)
		elif type == "select_upgrade":
			parent.receive_upgrade_selected(data.upgrade_data_id, data.player_id)
		elif type == "death":
			parent.receive_death(data.player_id)
		elif type == "undo_item_box":
			parent.receive_undo_item_box(data.player_id, data.item_id)
		elif type == "complete_player_update":
			parent.receive_complete_player_update(data.player_id)
		return true
	return false

func send_data_to_all(data: Dictionary):
	var compressed_data = var2bytes(data).compress(File.COMPRESSION_GZIP)
	for peer_id in parent.tracked_players.keys():
		if peer_id != parent.self_peer_id:
			Steam.sendP2PPacket(peer_id, compressed_data, Steam.P2P_SEND_RELIABLE, 0)

func send_start_game(game_info: Dictionary) -> void:
	var send_data = {"type": "start_game", "game_info": game_info}
	send_data_to_all(send_data)

func send_display_floating_text(text_info: Dictionary) -> void:
	var send_data = {"type": "floating_text", "text_info": text_info}
	send_data_to_all(send_data)

func send_display_hit_effect(effect_info: Dictionary) -> void:
	var send_data = {"type": "hit_effect", "effect_info": effect_info}
	send_data_to_all(send_data)

func send_enemy_death(enemy_id: int) -> void:
	var send_data = {"type": "enemy_death", "enemy_id": enemy_id}
	send_data_to_all(send_data)

func send_end_wave() -> void:
	var send_data = {"type": "end_wave"}
	send_data_to_all(send_data)

func send_flash_enemy(enemy_id: int) -> void:
	var send_data = {"type": "flash_enemy", "enemy_id": enemy_id}
	send_data_to_all(send_data)

func send_flash_neutral(neutral_id: int) -> void:
	var send_data = {"type": "flash_neutral", "neutral_id": neutral_id}
	send_data_to_all(send_data)

func send_client_position(client_position: Dictionary) -> void:
	var send_data = {"type": "client_position", "client_position": client_position}
	send_data_to_all(send_data)

func send_danger_selected(danger) -> void:
	var send_data = {"type": "danger_selected", "player_id": parent.self_peer_id, "danger": danger}
	send_data_to_all(send_data)

func send_character_selected(character) -> void:
	var send_data = {"type": "character_selected", "player_id": parent.self_peer_id, "character": character}
	send_data_to_all(send_data)

func send_weapon_selected(weapon) -> void:
	var send_data = {"type": "weapon_selected", "player_id": parent.self_peer_id, "weapon": weapon}
	send_data_to_all(send_data)

func send_mp_lobby_readied(is_ready: bool) -> void:
	var send_data = {"type": "mp_lobby_readied", "player_id": parent.self_peer_id, "is_ready": is_ready}
	send_data_to_all(send_data)

func send_reroll(price: int) -> void:
	var send_data = {"type": "reroll", "player_id": parent.self_peer_id, "price": price}
	send_data_to_all(send_data)

func send_reroll_upgrades(reroll_price: int) -> void:
	var send_data = {"type": "reroll_upgrades", "reroll_price": reroll_price}
	send_data_to_all(send_data)

func send_weapon_discard(weapon_id: String) -> void:
	var send_data = {"type": "weapon_discard", "weapon_id": weapon_id}
	send_data_to_all(send_data)

func send_client_entered_shop() -> void:
	var send_data = {"type": "client_entered_shop", "player_id": parent.self_peer_id}
	send_data_to_all(send_data)

func send_client_started() -> void:
	var send_data = {"type": "client_started", "player_id": parent.self_peer_id}
	send_data_to_all(send_data)

func send_tracked_players(tracked_players: Dictionary) -> void:
	var send_data = {"type": "tracked_players", "tracked_players": tracked_players}
	send_data_to_all(send_data)

func send_health_update(current_health: int, max_health: int) -> void:
	var send_data = {"type": "health_update", "current_health": current_health, "max_health": max_health}
	send_data_to_all(send_data)

func create_new_game_lobby():
	var result = Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 4)
	if result == Steam.RESULT_OK:
		pending_system_messages.append("Creating lobby...")

func _on_Lobby_Created(_connect, lobby):
	lobby_id = lobby
	parent.is_host = true
	parent.self_peer_id = Steam.getSteamID()
	parent.tracked_players[parent.self_peer_id] = {}
	pending_system_messages.append("Lobby created: " + str(lobby))

func _on_Lobby_Joined(lobby, _permissions, _locked, response):
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_id = lobby
		parent.self_peer_id = Steam.getSteamID()
		pending_system_messages.append("Joined lobby: " + str(lobby))
	else:
		pending_system_messages.append("Failed to join lobby: " + str(response))

func _on_Lobby_Match_List(lobbies):
	for lobby in lobbies:
		var lobby_name = Steam.getLobbyData(lobby, "name")
		emit_signal("game_lobby_found", lobby, lobby_name)

func _on_Lobby_Chat_Update(_lobby, _user_changed, _state, _user):
	pending_system_messages.append("Lobby chat updated")

func _on_P2P_Session_Request(remote_id):
	Steam.acceptP2PSessionWithUser(remote_id)
	established_p2p_connections[remote_id] = true

func send_global_chat_message(message: String):
	var sender = Steam.getSteamID()
	var username = Steam.getFriendPersonaName(sender)
	var data = {"type": "global_chat", "user": username, "message": message}
	var compressed_data = var2bytes(data).compress(File.COMPRESSION_GZIP)
	for peer_id in established_p2p_connections.keys():
		Steam.sendP2PPacket(peer_id, compressed_data, Steam.P2P_SEND_RELIABLE, 0)
	emit_signal("global_chat_received", username, message)

signal global_chat_received(user, message)
signal game_lobby_found(lobby_id, lobby_name)
