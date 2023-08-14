extends "res://effects/items/burn_chance_effect.gd"

func multiplayer_apply(run_data) -> void:
	run_data.effects["burn_chance"].merge(burning_data)

func multiplayer_unapply(run_data) -> void:
	run_data.effects["burn_chance"].remove(burning_data)
