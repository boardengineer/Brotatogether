extends "res://entities/units/unit/unit.gd"


func init(zone_min_pos:Vector2, zone_max_pos:Vector2, p_player_ref:Node2D = null, entity_spawner_ref:EntitySpawner = null) -> void:
	if not $"/root".has_node("GameController"):
		.init(zone_min_pos, zone_max_pos, p_player_ref, entity_spawner_ref)
		return
	
	.init(zone_min_pos, zone_max_pos, p_player_ref, entity_spawner_ref)
	
	var game_controller = $"/root/GameController"
	var reduction_sum = 0
	
	for player_id in game_controller.tracked_players:
		var run_data = game_controller.tracked_players[player_id].run_data
		reduction_sum += run_data.effects["burning_cooldown_reduction"]
	
	_burning_timer.wait_time = max(0.1, _burning_timer.wait_time * (1.0 - (reduction_sum / 100.0)))
