extends "res://mods-unpacked/Pasha-Brotatogether/networking/connection.gd"

var lobby_id = 0
var parent
var established_p2p_connections = {}

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
		prev_sec = sec
	
	if packet_size > 0:
		var packet = Steam.readP2PPacket(packet_size, 0)
		
		var sender = packet["steam_id_remote"]
		var data = bytes2var(packet["data"].decompress_dynamic(-1, File.COMPRESSION_GZIP))
		var type = data.type
		
		if not rpcs_by_type.has(type):
			rpcs_by_type[type] = 0
		rpcs_by_type[type] += 1
		
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
		elif type == "client_entered_shop":
			parent.receive_player_enter_shop(data.player_id)
		elif type == "client_started":
			parent.receive_client_start(data.player_id)
		elif type == "add_consumable_to_process":
			parent.receive_add_consumable_to_process(data.player_id, data.consumable_data_path)
		elif type == "end_wave":
			parent.end_wave()
		elif type == "level_up":
			parent.receive_player_level_up(data.player_id, data.level)
		elif type == "flash_neutral":
			parent.flash_neutral(data.neutral_id)
		elif type == "client_position_update":
			parent.update_client_position(data.client_position)
		elif type == "send_bought_item":
			parent.receive_bought_item(load(data.shop_item), sender)
		elif type == "send_bought_item_by_id":
			parent.receive_bought_item_by_id(data.item_id, sender, data.value)
		elif type == "send_ready":
			parent.update_ready_state(sender, data.is_ready)
		elif type == "request_complete_player":
			parent.send_complete_player(sender)
		elif type == "complete_player":
			parent.receive_complete_player(data.player_id, data.player_dict)
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
		elif type == "select_upgrade":
			parent.receive_uprade_selected(data.upgrade_data_id, sender)
		elif type == "shot":
			parent.receive_shot(data.player_id, data.weapon_index)
		elif type == "explosion":
			parent.receive_explosion(Vector2(data.pos_x, data.pos_y), data.scale)
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
				if parent.is_host:
					member_username = member_username + " (loading)"
		
		parent.tracked_players[member_steam_id] = {"username": member_username}
	
	parent.all_players_ready = all_players_ready
	parent.update_multiplayer_lobby()

func send_state(game_state:PoolByteArray) -> void:
	var send_data = {}
	send_data["game_state"] = game_state
	send_data["type"] = "game_state"
	
	for player_id in parent.tracked_players:
		if player_id == parent.self_peer_id:
			continue
		var compressed_data = var2bytes(send_data).compress(File.COMPRESSION_GZIP)
		
		# State updates get their own channel
		var _error = Steam.sendP2PPacket(player_id, compressed_data, Steam.P2P_SEND_RELIABLE, 1)

func send_start_game(game_info:Dictionary) -> void:
	var send_data = {}
	send_data["type"] = "start_game"
	send_data["game_info"] = game_info
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

func send_bought_item_by_id(item_id:String, value:int) -> void:
	var send_data = {}
	send_data["type"] = "send_bought_item_by_id"
	send_data["item_id"] = item_id
	send_data["value"] = value
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

func get_lobby_host() -> String:
	return Steam.getLobbyData(lobby_id,"host")

func send_upgrade_selection(upgrade_data_id) -> void:
	var send_data = {}
	send_data["type"] = "select_upgrade"
	send_data["upgrade_data_id"] = upgrade_data_id
	send_data_to_all(send_data)

func send_player_level_up(player_id:int, level:int) -> void:
	var send_data = {}
	send_data["type"] = "level_up"
	send_data["player_id"] = player_id
	send_data["level"] = level
	send_data_to_all(send_data)
	
func send_complete_player_request() -> void:
	var send_data = {}
	send_data["type"] = "request_complete_player"
	send_data_to_all(send_data)
	
func send_complete_player(player_id:int, player_dict:Dictionary) -> void:
	var send_data = {}
	send_data["type"] = "complete_player"
	send_data["player_id"] = player_id
	send_data["player_dict"] = player_dict
	send_data_to_all(send_data)

func send_add_consumable_to_process(player_id:int, consumable_data_path) -> void:
	var send_data = {}
	send_data["type"] = "add_consumable_to_process"
	send_data["player_id"] = player_id
	send_data["consumable_data_path"] = consumable_data_path
	send_data_to_all(send_data)

func send_take_item_box(player_id:int, item_id) -> void:
	var send_data = {}
	send_data["type"] = "send_take_item_box"
	send_data["player_id"] = player_id
	send_data["item_id"] = item_id
	send_data_to_all(send_data)

func send_combine_item(weapon_data_id, is_upgrade, player_id) -> void:
	var send_data = {}
	send_data["type"] = "send_combine_item"
	send_data["player_id"] = player_id
	send_data["is_upgrade"] = is_upgrade
	send_data["weapon_data_id"] = weapon_data_id
	send_data_to_all(send_data)

func send_discard_item_box(item_id) -> void:
	var send_data = {}
	send_data["type"] = "discard_item_box"
	send_data["item_id"] = item_id
	send_data_to_all(send_data)

func send_reroll_upgrades(reroll_price) -> void:
	var send_data = {}
	send_data["type"] = "reroll_upgrades"
	send_data["reroll_price"] = reroll_price
	send_data_to_all(send_data)

func send_weapon_discard(weapon_id) -> void:
	var send_data = {}
	send_data["type"] = "weapon_discard"
	send_data["weapon_id"] = weapon_id
	send_data_to_all(send_data)

func send_client_entered_shop() -> void:
	var send_data = {}
	send_data["type"] = "client_entered_shop"
	send_data["player_id"] = parent.self_peer_id
	send_data_to_all(send_data)

func send_client_started() -> void:
	var send_data = {}
	send_data["type"] = "client_started"
	send_data["player_id"] = parent.self_peer_id
	send_data_to_all(send_data)
