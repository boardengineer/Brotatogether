extends "res://projectiles/player_explosion.gd"


func start_explosion() -> void:
	var steam_connection = $"/root/SteamConnection"
	var brotatogether_options = $"/root/BrotogetherOptions"
	if brotatogether_options.in_multiplayer_game:
		if steam_connection.is_host():
			var explosion_dict = {
				"X_POS" : global_position.x,
				"Y_POS" : global_position.y,
				"SCALE" : scale.x,
			}
			brotatogether_options.batched_explosions.push_back(explosion_dict)
		.start_explosion()
	else:
		.start_explosion()
