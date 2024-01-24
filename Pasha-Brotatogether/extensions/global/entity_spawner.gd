extends "res://global/entity_spawner.gd"

var completed_turret_spawns = []

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
		
		if not completed_turret_spawns.has(player_id):
			spawn_all = true
			completed_turret_spawns.push_back(player_id)
		
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
	if not $"/root".has_node("GameController"):
		.on_group_spawn_timing_reached(group_data, _is_elite_wave)
		return
	
#	Cheat Spawn increases for trees and enemies by adding them up before the spawner function
	var trees = 0
	var number_of_enemies = 0
	
	var game_controller = $"/root/GameController"
	
	if $"/root/GameController".is_coop():
		for player_id in game_controller.tracked_players:
			var run_data = game_controller.tracked_players[player_id].run_data
			trees += run_data.effects.trees
			number_of_enemies += run_data.effects.number_of_enemies
		
	RunData.effects["trees"] = trees
	RunData.effects["number_of_enemies"] = number_of_enemies
	
	var enemies_multipliler = game_controller.lobby_data["enemy_count"]
	var new_group_data = WaveGroupData.new()
	new_group_data.wave_units_data = []
	
	for unit_wave_data in group_data.wave_units_data:
		var duped_data = unit_wave_data.duplicate()
		
		if unit_wave_data.type == EntityType.ENEMY:
			duped_data.min_number *= enemies_multipliler
			duped_data.max_number *= enemies_multipliler
			
		if group_data.is_boss and enemies_multipliler > 1:
			group_data.repeating = enemies_multipliler - 1 as int
			group_data.repeating_interval = 1
			group_data.min_repeating_interval = 1
		
		new_group_data.wave_units_data.push_back(duped_data)
	
	_current_wave_data.max_enemies = 10_000
	.on_group_spawn_timing_reached(new_group_data, _is_elite_wave)

func _physics_process(_delta:float)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return
	
	var game_controller = $"/root/GameController"
	var max_mult = game_controller.tracked_players.size()
	
	for _i in (max_mult / SPAWN_DELAY) + 1:
		if queue_to_spawn_structures.size() > 0:
			spawn(queue_to_spawn_structures)
		if queue_to_spawn_trees.size() > 0:
			spawn(queue_to_spawn_trees)
		if queue_to_spawn_bosses.size() > 0:
			spawn(queue_to_spawn_bosses)
		if queue_to_spawn_summons.size() > 0:
			spawn(queue_to_spawn_summons)
		if queue_to_spawn.size() > 0:
			spawn(queue_to_spawn)

