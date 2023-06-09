extends "res://mods-unpacked/Pasha-Brotatogether/networking/connection.gd"

var lobby_id = 0
var parent
var established_p2p_connections = {}

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
	
	if packet_size > 0:
		var packet = Steam.readP2PPacket(packet_size, 0)
		
		var sender = packet["steam_id_remote"]
		var data = bytes2var(packet["data"].decompress_dynamic(-1, File.COMPRESSION_GZIP))
		var type = data.type
		if type == "game_state":
			parent.update_game_state(data.game_state)
		elif type == "start_game":
			parent.start_game(data.game_info)
		elif type == "floating_text":
			parent.display_floating_text(data.text_info)
		elif type == "hit_effect":
			parent.display_hit_effect(data.effect_info)
		elif type == "enemy_death":
			parent.enemy_death(data.enemy_id)
		elif type == "end_wave":
			parent.end_wave()
		elif type == "flash_enemy":
			parent.flash_enemy(data.enemy_id)
		elif type == "flash_neutral":
			parent.flash_enemy(data.neutral_id)
		elif type == "client_position_update":
			parent.update_client_position(data.client_position)
		elif type == "send_bought_item":
			parent.receive_bought_item(load(data.shop_item), sender)
		elif type == "send_ready":
			parent.update_ready_state(sender, data.is_ready)
		elif type == "handshake":
			# completes the handshake?
			established_p2p_connections[sender] = true
			update_tracked_players()
			send_welcomes()
		elif type == "update_tracked_players":
			parent.update_tracked_players(data.tracked_players)
		elif type == "lobby_update":
			parent.receive_lobby_update(data.lobby_info)
		elif type == "health_update":
			parent.receive_health_update(data.current_health, data.max_health, sender)
		elif type == "death":
			parent.receive_death(sender)
		elif type == "shot":
			parent.receive_shot(data.player_id, data.weapon_index)
		elif type == "explosion":
			parent.receive_explosion(Vector2(data.pos_x, data.pos_y), data.scale)
		elif type == "enemy_take_damage":
			parent.receive_enemy_take_damage(data.enemy_id, data.is_dodge)
		elif type == "request_lobby_update":
			print_debug("received updated request")
			if get_tree().get_current_scene().get_name() == "MultiplayerLobby":
				var lobby_info = $"/root/MultiplayerLobby".get_lobby_info_dictionary()
				send_lobby_update(lobby_info)
		else:
			print_debug("unhandled type " , type)
		return true
	return false

func _on_Lobby_Match_List(lobbies: Array):
	var scene_name = get_tree().get_current_scene().get_name()
	if scene_name == "MultiplayerMenu":
		$"/root/MultiplayerMenu".update_lobbies(lobbies)
		pass


#	if lobbies.size() == 1:
#		Steam.joinLobby(lobbies[0])
#	pass

func _on_Lobby_Created(connect: int, connected_lobby_id: int) -> void:
	if connect == 1:
		lobby_id = connected_lobby_id
		
		var _set_error = Steam.setLobbyData(lobby_id, "game", "Brotatogether")
		_set_error = Steam.setLobbyData(lobby_id, "host", Steam.getPersonaName())
		
		var _error = Steam.allowP2PPacketRelay(false)

func close_lobby() -> void:
	# TODO this probably isn't the correct way to close a lobby but at least no one will find it
	# for now.
	var _set_error = Steam.setLobbyData(lobby_id, "game", "Not At All Brotatogether, Go Away")

func _on_Lobby_Joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response == 1:
		print_debug("on lobby joined")
		lobby_id = joined_lobby_id
		parent.self_peer_id = Steam.getSteamID()
		var _scene_error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_lobby.tscn")
		update_tracked_players()
		send_handshakes()
		
		if not parent.is_host:
			request_lobby_update()
	
func _on_Lobby_Chat_Update(_update_lobby_id: int, change_id: int, _making_change_id: int, chat_state: int) -> void:
	var username = Steam.getFriendPersonaName(change_id)
	update_tracked_players()
	
	if chat_state == 1:
		print_debug(username, " joined the lobby ", change_id)
		pass
		
	# Else if a player has left the lobby
	elif chat_state == 2:
		print_debug(username, " has left the lobby.")

	# Else if a player has been kicked
	elif chat_state == 8:
		print_debug(username, " has been kicked from the lobby.")

	# Else if a player has been banned
	elif chat_state == 16:
		print_debug(username, " has been banned from the lobby.")

# clears tracked_players and resets tracked players based  
func update_tracked_players() -> void:
	# Clear your previous lobby list
	parent.tracked_players.clear()

	# Get the number of members from this lobby from Steam
	var num_members = Steam.getNumLobbyMembers(lobby_id)
	var all_players_ready = true

	# Get the data of these players from Steam
	for member_index in range(num_members):
		var member_steam_id = Steam.getLobbyMemberByIndex(lobby_id, member_index)
		var member_username: String = Steam.getFriendPersonaName(member_steam_id)
		
		if not established_p2p_connections.has(member_steam_id) or not established_p2p_connections[member_steam_id]:
			if member_steam_id != parent.self_peer_id:
				all_players_ready = false
				member_username = member_username + " (loading)"
		
		parent.tracked_players[member_steam_id] = {"username": member_username}
	
	parent.all_players_ready = all_players_ready
	parent.update_multiplayer_lobby()

func send_state(game_state:PoolByteArray) -> void:
	var send_data = {}
	send_data["game_state"] = game_state
	send_data["type"] = "game_state"
	send_data_to_all(send_data)

func send_start_game(game_info:Dictionary) -> void:
	var send_data = {}
	send_data["type"] = "start_game"
	send_data["game_info"] = game_info
	send_data_to_all(send_data)
	
func send_display_floating_text(text_info:Dictionary) -> void:
	var send_data = {}
	send_data["type"] = "floating_text"
	send_data["text_info"] = text_info
	send_data_to_all(send_data)

func send_display_hit_effect(effect_info: Dictionary) -> void:
	var send_data = {}
	send_data["type"] = "hit_effect"
	send_data["effect_info"] = effect_info
	send_data_to_all(send_data)

func send_enemy_death(enemy_id):
	var send_data = {}
	send_data["type"] = "enemy_death"
	send_data["enemy_id"] = enemy_id
	send_data_to_all(send_data)
			
func send_end_wave():
	var send_data = {}
	send_data["type"] = "end_wave"
	send_data_to_all(send_data)

func send_shot(player_id:int, weapon_index:int) -> void:
	var send_data = {}
	send_data["type"] = "shot"
	send_data["player_id"] = player_id
	send_data["weapon_index"] = weapon_index
	send_data_to_all(send_data)
	
func send_flash_enemy(enemy_id):
	var send_data = {}
	send_data["type"] = "flash_enemy"
	send_data["enemy_id"] = enemy_id
	send_data_to_all(send_data)
	
func send_flash_neutral(neutral_id):
	var send_data = {}
	send_data["type"] = "flash_neutral"
	send_data["neutral_id"] = neutral_id
	send_data_to_all(send_data)

func send_data_to_all(packet_data: Dictionary):
	for player_id in parent.tracked_players:
		if player_id == parent.self_peer_id:
			continue
		send_data(packet_data, player_id)

func send_data(packet_data: Dictionary, target: int):
	# TODO actually compress
	var compressed_data = var2bytes(packet_data).compress(File.COMPRESSION_GZIP)
	
	# Just use channel 0 for everything for now
	var _error = Steam.sendP2PPacket(target, compressed_data, Steam.P2P_SEND_RELIABLE, 0)
	
# Done to trigger p2p session requests
func send_handshakes() -> void:
	var send_data = {}
	send_data["type"] = "handshake"
	send_data_to_all(send_data)
	
func send_welcomes() -> void:
	var send_data = {}
	send_data["type"] = "welcome"
	send_data_to_all(send_data)

func _on_P2P_Session_Request(remote_id: int) -> void:
	var _error = Steam.acceptP2PSessionWithUser(remote_id)

	# Make the initial handshake
	send_handshakes()

func send_client_position(client_position:Dictionary) -> void:
	var send_data = {}
	send_data["type"] = "client_position_update"
	send_data["client_position"] = client_position
	send_data_to_all(send_data)
	
func send_bought_item(shop_item:Resource) -> void:
	var send_data = {}
	send_data["type"] = "send_bought_item"
	send_data["shop_item"] = shop_item.get_path()
	send_data_to_all(send_data)

func send_ready(is_ready:bool) -> void:
	print_debug("sending ready")
	var send_data = {}
	send_data["type"] = "send_ready"
	send_data["is_ready"] = is_ready
	send_data_to_all(send_data)

func send_tracked_players(tracked_players:Dictionary) -> void:
	var send_data = {}
	send_data["type"] = "update_tracked_players"
	send_data["tracked_players"] = tracked_players
	send_data_to_all(send_data)
	
func send_lobby_update(lobby_info:Dictionary) -> void:
	var send_data = {}
	send_data["type"] = "lobby_update"
	send_data["lobby_info"] = lobby_info
	send_data_to_all(send_data)

func request_lobby_update() -> void:
	var send_data = {}
	send_data["type"] = "request_lobby_update"
	send_data_to_all(send_data)

func send_health_update(current_health:int, max_health:int) -> void:
	var send_data = {}
	send_data["type"] = "health_update"
	send_data["current_health"] = current_health
	send_data["max_health"] = max_health
	send_data_to_all(send_data)

func send_death() -> void:
	var send_data = {}
	send_data["type"] = "death"
	send_data_to_all(send_data)

func send_explosion(pos: Vector2, scale: float) -> void:
	var send_data = {}
	send_data["type"] = "explosion"
	send_data["pos_x"] = pos.x
	send_data["pos_y"] = pos.y
	send_data["scale"] = scale
	send_data_to_all(send_data)

func send_enemy_take_damage(enemy_id:int, is_dodge:bool) -> void:
	var send_data = {}
	send_data["type"] = "enemy_take_damage"
	send_data["enemy_id"] = enemy_id
	send_data["is_dodge"] = is_dodge
	send_data_to_all(send_data)

func get_lobby_host() -> String:
	return Steam.getLobbyData(lobby_id,"host")
