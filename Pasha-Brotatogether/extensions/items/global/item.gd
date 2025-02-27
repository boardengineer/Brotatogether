extends "res://items/global/item.gd"

var steam_connection
var brotatogether_options
var in_multiplayer_game = false
var network_id = 0
var is_host = false


func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"
	in_multiplayer_game = brotatogether_options.in_multiplayer_game
	
	if in_multiplayer_game:
		is_host = steam_connection.is_host()
		network_id = brotatogether_options.current_network_id
		brotatogether_options.current_network_id = brotatogether_options.current_network_id + 1
