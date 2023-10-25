extends ChargingAttackBehavior

func start_shoot()->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.start_shoot()
		return
	
	var player_pos = _parent.player_ref.global_position
	
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
		player_pos = closest_player.global_position
	else:
		return
	
	if target == TargetType.PLAYER:
		_charge_direction = (_parent.player_ref.global_position - _parent.global_position)
	else :
		var target_pos = player_pos + Vector2(rand_range( - max_range / 5, max_range / 5), rand_range( - max_range / 5, max_range / 5))
		_charge_direction = (target_pos - _parent.global_position)
	
	_parent._can_move = false
