extends Node

const GLOBAL_CHAT_TYPE := "BROTATOGETHER_GLOBAL_CHAT"
const GAME_LOBBY_TYPE := "BROTATOGETHER_GAME_LOBBY"


var global_chat_lobby_id : int = -1
var game_lobby_id : int = -1

var is_querying_global_chat := false

var is_creating_global_chat_lobby : bool = false
var global_chat_check_timer : Timer

signal global_chat_received (username, message)
signal game_lobby_chat_received (username, message)

func _ready():
	if not Steam.loggedOn():
		return
	
	var _err
	
	_err = Steam.connect("lobby_match_list", self, "_on_lobby_match_list")
	_err = Steam.connect("lobby_created", self, "_on_lobby_created")
	_err = Steam.connect("lobby_joined", self, "_on_lobby_joined")
	_err = Steam.connect("lobby_message", self, "_on_lobby_message")
	_err = Steam.connect("lobby_chat_update", self, "_on_lobby_chat_update")
	
	global_chat_check_timer = Timer.new()
	_err = global_chat_check_timer.connect("timeout", self, "_request_global_chat_search")
	add_child(global_chat_check_timer)
	global_chat_check_timer.start(3.0)
	
	_request_global_chat_search()


func _process(_delta: float) -> void:
	Steam.run_callbacks()


func send_global_chat_message(message : String) -> void:
	var _err = Steam.sendLobbyChatMsg(global_chat_lobby_id, message)


func send_lobby_chat_message(message : String) -> void:
	var _err = Steam.sendLobbyChatMsg(game_lobby_id, message)


func _on_lobby_match_list(lobbies: Array) -> void:
	var found_global_chat_lobby : bool = false
	var min_chat_lobby_id : int = -1
	
	for lobby_id in lobbies:
		var lobby_data : Dictionary = Steam.getAllLobbyData(lobby_id)
		for kvpair_index in lobby_data:
			var key = lobby_data[kvpair_index]["key"]
			var value = lobby_data[kvpair_index]["value"]
			if key == "lobby_type" and value == GLOBAL_CHAT_TYPE:
				if not found_global_chat_lobby:
					min_chat_lobby_id = lobby_id
			
				if lobby_id < min_chat_lobby_id:
					min_chat_lobby_id = lobby_id
				
				found_global_chat_lobby = true
	
	if min_chat_lobby_id < global_chat_lobby_id:
		print_debug("Not sure how this happened but we should rejoin the lower id chat room")
	
	if found_global_chat_lobby:
		if min_chat_lobby_id != global_chat_lobby_id:
			Steam.joinLobby(min_chat_lobby_id)
	else:
		is_creating_global_chat_lobby = true
		Steam.createLobby(Steam.LOBBY_TYPE_INVISIBLE, 250)


func _on_lobby_created(connect: int, created_lobby_id: int) -> void:
	if connect == 1:
		if is_creating_global_chat_lobby:
			is_creating_global_chat_lobby = false
			global_chat_lobby_id = created_lobby_id
			var _err = Steam.setLobbyData(created_lobby_id, "lobby_type", GLOBAL_CHAT_TYPE)
		else:
			game_lobby_id = created_lobby_id
			var _err = Steam.setLobbyData(created_lobby_id, "lobby_type", GAME_LOBBY_TYPE)


func _request_global_chat_search() -> void:
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("lobby_type", GLOBAL_CHAT_TYPE, Steam.LOBBY_COMPARISON_EQUAL)
	
	Steam.requestLobbyList()


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		var lobby_data : Dictionary = Steam.getAllLobbyData(lobby_id)
		print_debug("joined lobby %s" % lobby_data)
		for kvpair_index in lobby_data:
			var key = lobby_data[kvpair_index]["key"]
			var value = lobby_data[kvpair_index]["value"]
			if key == "lobby_type":
				if value == GLOBAL_CHAT_TYPE:
					global_chat_lobby_id = lobby_id
				elif value == GAME_LOBBY_TYPE:
					$"/root/BrotogetherOptions".joining_multiplayer_lobby = true
					game_lobby_id = lobby_id
					var _error = get_tree().change_scene(MenuData.character_selection_scene)


func _on_lobby_chat_update(_lobby_id: int, change_id: int, _making_change_id: int, chat_state: int) -> void:
	# Get the user who has made the lobby change
	var changer_name: String = Steam.getFriendPersonaName(change_id)

	# If a player has joined the lobby
	if chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
		print("%s has joined the lobby." % changer_name)

	# Else if a player has left the lobby
	elif chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_LEFT:
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


func _on_lobby_message(lobby_id : int, user_id : int, buffer : String, _chat_type : int) -> void:
	if lobby_id == global_chat_lobby_id:
		emit_signal("global_chat_received", Steam.getFriendPersonaName(user_id), buffer)
	elif lobby_id == game_lobby_id:
		emit_signal("game_lobby_chat_received", Steam.getFriendPersonaName(user_id), buffer)


func create_new_game_lobby() -> void:
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 4)
