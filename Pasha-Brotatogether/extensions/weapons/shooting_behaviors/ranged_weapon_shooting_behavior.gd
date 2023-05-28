extends RangedWeaponShootingBehavior

func shoot(_distance:float)->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
			return
	.shoot(_distance)
	
func shoot_projectile(rotation:float = _parent.rotation, knockback:Vector2 = Vector2.ZERO)->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
			return
	.shoot_projectile(rotation, knockback)
