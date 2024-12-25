extends "res://global/entity_spawner.gd"

var steam_connection
var brotatogether_options


func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"


func spawn(queue_from: Array, player_index: = - 1) -> void:
	if not brotatogether_options.in_multiplayer_game:
		.spawn(queue_from, player_index)
		return
	
	if not steam_connection.is_host():
		queue_from.pop_back()
		return
	
	.spawn(queue_from, player_index)
