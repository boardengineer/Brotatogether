extends "res://global/entity_spawner.gd"

func _on_StructureTimer_timeout() -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		._on_StructureTimer_timeout()
		return
		
	if _cleaning_up:
		return
		 
	var cur_time = ((_wave_timer.wait_time - _wave_timer.time_left) as int)
	
	var game_controller = $"/root/GameController"
	
	for player_id in game_controller.tracked_players:
		var run_data = game_controller.tracked_players[player_id].run_data
		
		var spawn_radius = min(600, 400 + (run_data.effects["structures"].size() * 10)) as int
		var base_pos = ZoneService.get_rand_pos(600 + Utils.EDGE_MAP_DIST)
		var _nb_turrets = 0
		var spawn_all = false
		
		if not _base_structures_spawned:
			spawn_all = true
			_base_structures_spawned = true
		
		for struct in run_data.effects["structures"]:
			var spawn_cd = struct.spawn_cooldown
			
			if struct.spawn_cooldown != - 1 and run_data.effects["structures_cooldown_reduction"].size() > 0:
				spawn_cd = Utils.apply_cooldown_reduction(spawn_cd, run_data.effects["structures_cooldown_reduction"])
			
			if (spawn_cd != - 1 and cur_time % spawn_cd == 0) or spawn_all:
				
				if struct is TurretEffect:
					_nb_turrets += 1
				
				for nb in struct.value:
					var pos = get_spawn_pos_in_area(base_pos, spawn_radius) if run_data.effects["group_structures"] and struct.can_be_grouped else ZoneService.get_rand_pos((Utils.EDGE_MAP_DIST * 2.5) as int)
					
					if struct.spawn_around_player != - 1:
						pos = get_spawn_pos_in_area(_player.global_position, struct.spawn_around_player)
					
					queue_to_spawn_structures.push_back([EntityType.STRUCTURE, struct.scene, pos, struct])
					
					
func on_group_spawn_timing_reached(group_data:WaveGroupData, _is_elite_wave:bool) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.on_group_spawn_timing_reached(group_data, _is_elite_wave)
		return
	
#	Cheat Spawn increases for trees and enemies by adding them up before the spawner function
	var trees = 0
	var number_of_enemies = 0
	
	var game_controller = $"/root/GameController"
	
	for player_id in game_controller.tracked_players:
		var run_data = game_controller.tracked_players[player_id].run_data
		trees += run_data.effects.trees
		number_of_enemies += run_data.effects.number_of_enemies
		
	RunData.effects["trees"] = trees
	
	var additinonal_enemies_multipliler = (game_controller.tracked_players.size() - 1) * 75
	
	RunData.effects["number_of_enemies"] = number_of_enemies + additinonal_enemies_multipliler
	
	.on_group_spawn_timing_reached(group_data, _is_elite_wave)
