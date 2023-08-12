extends "res://effects/items/burn_chance_effect.gd"

func multiplayer_apply(run_data):
	run_data.effects["burn_chance"].merge(burning_data)
