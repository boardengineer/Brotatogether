extends Node

const GLOBAL_CHAT_TYPE := "BROTATOGETHER_GLOBAL_CHAT"
const GAME_LOBBY_TYPE := "BROTATOGETHER_GAME_LOBBY"

var global_chat_lobby_id := -1
var is_querying_global_chat := false

var is_creating_global_chat_lobby : bool = false
var global_chat_check_timer : Timer

func _ready():
	if not Steam.loggedOn():
		return
	
	var _err
	
	_err = Steam.connect("lobby_match_list", self, "_on_lobby_match_list")
	_err = Steam.connect("lobby_created", self, "_on_lobby_created")
	
	global_chat_check_timer = Timer.new()
	global_chat_check_timer.connect("timeout", self, "_request_global_chat_search")
	add_child(global_chat_check_timer)
	global_chat_check_timer.start(3.0)


func _process(_delta: float) -> void:
	Steam.run_callbacks()


func _input(event):
	if event is InputEventKey and event.pressed:
		if event.scancode == KEY_F1:
			Steam.requestLobbyList()
		elif event.scancode == KEY_F2:
			print_debug("creating lobby...")
			Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 5)


func _on_lobby_match_list(lobbies: Array) -> void:
	print_debug("found lobby match")
	
	var found_global_chat_lobby : bool = false
	var min_chat_lobby_id := -1
	
	for lobby_id in lobbies:
		var lobby_data : Dictionary = Steam.getAllLobbyData(lobby_id)
		print_debug("found lobby id: [%d], kvpairs: [%s]" % [lobby_id , lobby_data])
		for kvpair_index in lobby_data:
			var key = lobby_data[kvpair_index]["key"]
			var value = lobby_data[kvpair_index]["value"]
			print_debug("key value : {%s  %s}" % [key, value])
			if key == "lobby_type" and value == GLOBAL_CHAT_TYPE:
				if not found_global_chat_lobby:
					min_chat_lobby_id = lobby_id
			
				min_chat_lobby_id = min(min_chat_lobby_id, lobby_id)
				found_global_chat_lobby = true
	
	if min_chat_lobby_id < global_chat_lobby_id:
		print_debug("Not sure how this happened but we should rejoin the lower id chat room")
	
	if not found_global_chat_lobby:
		print_debug("no global chat lobby found, creating one")
		is_creating_global_chat_lobby = true
		Steam.createLobby(Steam.LOBBY_TYPE_INVISIBLE, 250)
	
	print_debug("End of Lobby List")


func _on_lobby_created(connect: int, created_lobby_id: int) -> void:
	if connect == 1:
		if is_creating_global_chat_lobby:
			is_creating_global_chat_lobby = false
			print_debug("creating chat lobby")
			global_chat_lobby_id = created_lobby_id
			Steam.setLobbyData(created_lobby_id, "lobby_type", GLOBAL_CHAT_TYPE)
	print_debug("lobby created connect: %d  lobby_id : %d" % [connect, created_lobby_id])


func _request_global_chat_search() -> void:
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("lobby_type", GLOBAL_CHAT_TYPE, Steam.LOBBY_COMPARISON_EQUAL)
	
	Steam.requestLobbyList()
