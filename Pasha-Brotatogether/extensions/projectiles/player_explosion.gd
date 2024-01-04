extends "res://projectiles/player_explosion.gd"

func set_area_multiplayer(player_id, p_area:float)->void :
	var multiplayer_utils = $"/root/MultiplayerUtils"
	
	var explosion_scale = max(0.1, p_area + (p_area * (multiplayer_utils.get_stat_multiplayer(player_id, "explosion_size") / 100.0)))
	scale = Vector2(explosion_scale, explosion_scale)
