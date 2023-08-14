extends "res://effects/items/structure_effect.gd"

var player_id = -1

func multiplayer_apply(run_data) -> void:
	player_id = run_data.player_id
	run_data.effects["structures"].push_back(self)

func multiplayer_unapply(run_data) -> void:
	run_data.effects["structures"].erase(self)
