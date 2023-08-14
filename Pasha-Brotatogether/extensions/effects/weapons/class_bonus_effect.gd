extends "res://effects/items/class_bonus_effect.gd"

func multiplayer_apply(run_data) -> void:
	run_data.effects["weapon_class_bonus"].push_back([set_id, stat_name, value])

func multiplayer_unapply(run_data) -> void:
	run_data.effects["weapon_class_bonus"].erase([set_id, stat_name, value])
