extends MeleeWeaponShootingBehavior

func shoot(distance:float)->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared":
			for player_id in game_controller.tracked_players:
				var player = game_controller.tracked_players[player_id]["player"]
				for weapon_index in player.current_weapons.size():
					if player.current_weapons[weapon_index] == _parent:
						game_controller.send_shot(player_id, weapon_index)
	.shoot(distance)
