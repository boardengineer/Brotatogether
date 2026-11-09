extends "res://projectiles/player_explosion.gd"

var is_ghost_explosion = false

func start_explosion() -> void:
	var steam_connection = $"/root/SteamConnection"
	var brotatogether_options = $"/root/BrotogetherOptions"
	if brotatogether_options.in_multiplayer_game and not is_ghost_explosion:
		if steam_connection.is_host():
			var explosion_dict = {
				"X_POS" : global_position.x,
				"Y_POS" : global_position.y,
				"SCALE" : scale.x,
			}
			brotatogether_options.batched_explosions.push_back(explosion_dict)
		.start_explosion()
	elif is_ghost_explosion:
		# The base start_explosion (1.2) also rolls the owner's fire-explosion effect, keyed by
		# player_index -- -1 on a replayed explosion, which asserts in get_player_effect. The
		# host's fire puddle arrives in its PUDDLES rows, so a replay only plays the visual.
		_hitbox.enable()
		_hitbox.from = self
		_sprite.modulate.a = ProgressData.settings.explosion_opacity
		_animation_player.play("explode")
	else:
		.start_explosion()
