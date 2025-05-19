extends "res://projectiles/player_projectile.gd"

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


func _get_player_index()->int:
	if self.in_multiplayer_game:
		if not self.is_host:
			return 0
	return ._get_player_index() 


func _on_Hitbox_hit_something(thing_hit: Node, damage_dealt: int) -> void :
	if self.in_multiplayer_game:
		if not self.is_host:
			return
	._on_Hitbox_hit_something(thing_hit, damage_dealt)
