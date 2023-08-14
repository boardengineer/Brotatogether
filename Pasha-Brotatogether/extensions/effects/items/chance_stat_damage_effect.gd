extends "res://effects/items/chance_stat_damage_effect.gd"


func multiplayer_apply(run_data) -> void:
	run_data.effects[custom_key].push_back([key, value, chance])

func multiplayer_unapply(run_data) -> void:
	run_data.effects[custom_key].erase([key, value, chance])
