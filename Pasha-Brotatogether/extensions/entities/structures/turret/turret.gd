extends "res://entities/structures/turret/turret.gd"


func shoot()->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.shoot()
		return
	
	if _current_target.size() == 0 or not is_instance_valid(_current_target[0]):
		_is_shooting = false
		_cooldown = rand_range(max(1, _max_cooldown * 0.7), _max_cooldown * 1.3)
	else :
		_next_proj_rotation = (_current_target[0].global_position - global_position).angle()

	SoundManager2D.play(Utils.get_rand_element(stats.shooting_sounds), global_position, stats.sound_db_mod, 0.2)

	for i in stats.nb_projectiles:
		var proj_rotation = rand_range(_next_proj_rotation - stats.projectile_spread, _next_proj_rotation + stats.projectile_spread)
		var knockback_direction: = - Vector2(cos(proj_rotation), sin(proj_rotation))
		var projectile = WeaponService.spawn_projectile(proj_rotation, 
			stats, 
			_muzzle.global_position, 
			knockback_direction, 
			false, 
			effects
		)
		call_deferred("connect_projectile", projectile)


func connect_projectile(projectile) -> void:
	var player_id = get_node("StrcutureData").data["owner_player_id"]
	
	var run_data_node = $"/root/MultiplayerRunData"
	run_data_node.hitbox_to_owner_map[projectile.get_node("Hitbox")] = player_id
	pass
