extends "res://effects/weapons/gain_stat_every_killed_enemies_effect.gd"

func multiplayer_apply(run_data) -> void:
	self.player_id = run_data.player_id
	.multiplayer_apply(run_data)
