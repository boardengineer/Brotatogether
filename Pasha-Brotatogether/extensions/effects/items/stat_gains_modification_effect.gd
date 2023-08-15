extends "res://effects/items/stat_gains_modification_effect.gd"

func multiplayer_apply(run_data) -> void:
	for stat in stats_modified:
		run_data.effects["gain_" + stat] += value

func multiplayer_unapply(run_data) -> void:
	for stat in stats_modified:
		run_data.effects["gain_" + stat] -= value
