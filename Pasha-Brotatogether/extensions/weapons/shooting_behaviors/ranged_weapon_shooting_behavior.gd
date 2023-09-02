extends RangedWeaponShootingBehavior

func shoot(distance:float) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.shoot(distance)
		return
	
	var game_controller = $"/root/GameController"
	if not game_controller.is_host:
		return
	
	for player_id in game_controller.tracked_players:
		var player = game_controller.tracked_players[player_id]["player"]
		for weapon_index in player.current_weapons.size():
			if player.current_weapons[weapon_index] == _parent:
				game_controller.send_shot(player_id, weapon_index)
	
	.shoot(distance)
	
func shoot_projectile(rotation:float = _parent.rotation, knockback:Vector2 = Vector2.ZERO)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.shoot_projectile(rotation, knockback)
		return
	
	var game_controller = $"/root/GameController"
	var run_data_node = $"/root/MultiplayerRunData"
	
	if not game_controller.is_host:
		return
		
	var projectile = WeaponService.spawn_projectile(rotation, 
		_parent.current_stats, 
		_parent.muzzle.global_position, 
		knockback, 
		false, 
		_parent.effects, 
		_parent
	)
	
	for player_id in game_controller.tracked_players:
		var player = game_controller.tracked_players[player_id]["player"]
		for weapon_index in player.current_weapons.size():
			if player.current_weapons[weapon_index] == _parent:
				run_data_node.hitbox_to_owner_map[projectile._hitbox] = player_id
	
	if _parent.effects.size() > 0 and is_instance_valid(projectile):
		var _killed_sthing = projectile._hitbox.connect("killed_something", _parent.get_node("data_node"), "on_killed_something")
	
	var _hit_sthing = projectile.connect("hit_something", _parent, "on_weapon_hit_something")
