extends "res://weapons/weapon.gd"

var steam_connection
var brotatogether_options
var in_multiplayer_game = false
var is_host = false


func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"
	in_multiplayer_game = brotatogether_options.in_multiplayer_game
	is_host = steam_connection.is_host()


func get_direction_and_calculate_target() -> float:
	if in_multiplayer_game:
		if not is_host:
			return rotation
	return .get_direction_and_calculate_target()


func get_direction() -> float:
	if in_multiplayer_game:
		if not is_host:
			return rotation
	return .get_direction()
