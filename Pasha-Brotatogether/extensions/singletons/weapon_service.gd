extends "res://singletons/weapon_service.gd"

func explode(effect:Effect, pos:Vector2, damage:int, accuracy:float, crit_chance:float, crit_dmg:float, burning_data:BurningData, is_healing:bool = false, ignored_objects:Array = [], damage_tracking_key:String = "")->Node:
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		game_controller.send_explosion(pos, effect.scale)
	return .explode(effect, pos, damage, accuracy, crit_chance, crit_dmg, burning_data, is_healing, ignored_objects, damage_tracking_key)
