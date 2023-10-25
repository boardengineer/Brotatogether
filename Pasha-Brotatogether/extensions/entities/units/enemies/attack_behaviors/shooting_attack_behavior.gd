extends ShootingAttackBehavior

func shoot() -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.shoot()
		return
	
	var target_pos = _parent.player_ref.global_position
	
	var game_controller = $"/root/GameController"
	if game_controller.is_host:
		var entity_spawner = $"/root/Main"._entity_spawner
		var closest_square_length = -1
		var enemy_position = _parent.global_position
		var closest_player
		for entity in entity_spawner._entities_container.get_children():
			if entity is Player:
				var square_distance = entity.global_position.distance_squared_to(enemy_position)
				if closest_square_length == -1 or closest_square_length > square_distance:
					closest_square_length = square_distance
					closest_player = entity
		target_pos = closest_player.global_position
	else:
		return
	
	if shoot_in_unit_direction:
		target_pos = _parent.global_position + _parent.get_movement()
	
	for i in number_projectiles:
		var base_rot = (target_pos - _parent.global_position).angle()
		var rotation = rand_range(base_rot - projectile_spread, base_rot + projectile_spread)
		
		if random_direction:
			rotation = rand_range( - PI, PI)
		
		if constant_spread and number_projectiles > 1:
			var chunk = (2 * projectile_spread) / (number_projectiles - 1)
			var start = base_rot - projectile_spread
			rotation = start + (i * chunk)
		
		var pos = _parent.global_position
		
		if spawn_projectiles_on_target:
			pos = target_pos
		
		if projectile_spawn_only_on_borders:
			var rand = rand_range(0, 2 * PI)
			
			if constant_spread:
				rand = i * ((2 * PI) / number_projectiles)
			
			pos = Vector2(pos.x + cos(rand) * (projectile_spawn_spread / 2), pos.y + sin(rand) * (projectile_spawn_spread / 2))
		elif not atleast_one_projectile_on_target or i != 0:
			pos = Vector2(
				rand_range(pos.x - projectile_spawn_spread / 2, pos.x + projectile_spawn_spread / 2), 
				rand_range(pos.y - projectile_spawn_spread / 2, pos.y + projectile_spawn_spread / 2)
			)
		
		var _projectile = spawn_projectile(rotation, pos)
