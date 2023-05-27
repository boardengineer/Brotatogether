extends RangedWeaponShootingBehavior

onready var game_controller = $"/root/GameController"

func shoot(_distance:float)->void :
	if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
		return
	.shoot(_distance)
	
func shoot_projectile(rotation:float = _parent.rotation, knockback:Vector2 = Vector2.ZERO)->void :
	if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
		return
	.shoot_projectile(rotation, knockback)
