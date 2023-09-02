extends MeleeWeaponShootingBehavior

func shoot(distance:float)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.shoot(distance)
		return 
		
	var game_controller = $"/root/GameController"
	for player_id in game_controller.tracked_players:
		var player = game_controller.tracked_players[player_id]["player"]
		for weapon_index in player.current_weapons.size():
			if player.current_weapons[weapon_index] == _parent:
				game_controller.send_shot(player_id, weapon_index)
	
	.shoot(distance)
