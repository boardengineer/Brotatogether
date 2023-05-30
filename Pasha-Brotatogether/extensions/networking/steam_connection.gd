extends "res://mods-unpacked/Pasha-Brotatogether/extensions/networking/connection.gd"

var lobby_id = 0
var parent

func _ready():
	Steam.connect("lobby_created", self, "_on_Lobby_Created")
	Steam.connect("lobby_match_list", self, "_on_Lobby_Match_List")
	Steam.connect("lobby_joined", self, "_on_Lobby_Joined")
	Steam.connect("lobby_chat_update", self, "_on_Lobby_Chat_Update")
	Steam.connect("p2p_session_request", self, "_on_P2P_Session_Request")

func _process(delta):
	if lobby_id > 0:
		while read_p2p_packet():
			pass

func read_p2p_packet() -> bool:
	var packet_size = Steam.getAvailableP2PPacketSize(0)
	
	if packet_size > 0:
		print_debug("reading packet")
		var packet = Steam.readP2PPacket(packet_size, 0)
		
		var sender = packet["steam_id_remote"]
		var data = bytes2var(packet["data"])
		
		var type = data.type
		if type == "game_state":
			print_debug("game state received", data.game_state)
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
			send_welcomes()
		else:
			print_debug("unhandled type " , type)
		return true
	return false

func _on_Lobby_Match_List(lobbies: Array):
	print_debug("lobbies ", lobbies)
	var scene_name = get_tree().get_current_scene().get_name()
	if scene_name == "MultiplayerMenu":
		$"/root/MultiplayerMenu".update_lobbies(lobbies)
		pass
#
#	if lobbies.size() == 1:
#		Steam.joinLobby(lobbies[0])
#	pass

func _on_Lobby_Created(connect: int, connected_lobby_id: int) -> void:
	if connect == 1:
		print_debug("Lobby Created: ", connected_lobby_id)
		lobby_id = connected_lobby_id
		
		Steam.setLobbyData(lobby_id, "game", "Brotatogether")
		Steam.setLobbyData(lobby_id, "host", str(Steam.getSteamID()))
		
		Steam.allowP2PPacketRelay(false)
	pass

func _on_Lobby_Joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response == 1:
		lobby_id = joined_lobby_id
		parent.self_peer_id = Steam.getSteamID()
		get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_lobby.tscn")
		update_tracked_players()
		send_handshakes()
		print_debug("joined lobby ", lobby_id, " as ", parent.self_peer_id, " with permissions ", _permissions)
	else:
		print_debug("Lobby Join Failed with code ", response)
	
func _on_Lobby_Chat_Update(lobby_id: int, change_id: int, making_change_id: int, chat_state: int) -> void:
	print_debug("someone joined?")
	var username = Steam.getFriendPersonaName(change_id)
	update_tracked_players()
	
	if chat_state == 1:
		print_debug(username, " joined the lobby")
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
	print_debug("updating tracked players")
	# Clear your previous lobby list
	parent.tracked_players.clear()

	# Get the number of members from this lobby from Steam
	var num_members = Steam.getNumLobbyMembers(lobby_id)

	# Get the data of these players from Steam
	for member_index in range(num_members):
		var member_steam_id = Steam.getLobbyMemberByIndex(lobby_id, member_index)
		var member_username: String = Steam.getFriendPersonaName(member_steam_id)
		
		parent.tracked_players[member_steam_id] = {"username": member_username}
		print_debug(parent.tracked_players)

func send_state(game_state:Dictionary) -> void:
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

func send_flash_enemy(enemy_id):
	var send_data = {}
	send_data["type"] = "flash_enemy"
	send_data["enemy_id"] = enemy_id
	send_data_to_all(send_data)
			
func send_flash_neutral(neutral_id):
	var send_data = {}
	send_data["type"] = "flash_enemy"
	send_data["neutral_id"] = neutral_id
	send_data_to_all(send_data)

func send_data_to_all(packet_data: Dictionary):
	for player_id in parent.tracked_players:
		if player_id == parent.self_peer_id:
			continue
		send_data(packet_data, player_id)

func send_data(packet_data: Dictionary, target: int):
	var compressed_data = var2bytes(packet_data)
	
	# Just use channel 0 for everything for now
	Steam.sendP2PPacket(target, compressed_data, Steam.P2P_SEND_RELIABLE, 0)
	
# Done to trigger p2p session requests
func send_handshakes() -> void:
	print_debug("shaking hands")
	var send_data = {}
	send_data["type"] = "handshake"
	send_data_to_all(send_data)
	
func send_welcomes() -> void:
	print_debug("Welcoming shaker")
	var send_data = {}
	send_data["type"] = "welcome"
	send_data_to_all(send_data)

func _on_P2P_Session_Request(remote_id: int) -> void:
	print("_on_P2P_Session_Request")
	Steam.acceptP2PSessionWithUser(remote_id)

	# Make the initial handshake
	send_handshakes()

func send_client_position(client_position:Dictionary) -> void:
	print_debug("shaking hands")
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
	var send_data = {}
	send_data["type"] = "send_ready"
	send_data["is_ready"] = is_ready
	send_data_to_all(send_data)
