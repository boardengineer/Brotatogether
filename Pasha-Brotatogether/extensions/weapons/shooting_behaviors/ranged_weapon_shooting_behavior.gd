extends RangedWeaponShootingBehavior

func shoot(_distance:float)->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
			return
		for player_id in game_controller.tracked_players:
			var player = game_controller.tracked_players[player_id]["player"]
			for weapon_index in player.current_weapons.size():
				if player.current_weapons[weapon_index] == _parent:
					game_controller.send_shot(player_id, weapon_index)
	.shoot(_distance)
	
func shoot_projectile(rotation:float = _parent.rotation, knockback:Vector2 = Vector2.ZERO)->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
			return
	.shoot_projectile(rotation, knockback)
