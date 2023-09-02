extends FollowPlayerMovementBehavior

func get_movement()->Vector2:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return .get_movement()
	
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
		return closest_player.global_position - _parent.global_position
	return .get_movement()
