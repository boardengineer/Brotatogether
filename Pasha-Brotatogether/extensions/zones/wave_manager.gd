extends WaveManager

#var test_group = preload("res://mods-unpacked/Pasha-Brotatogether/opponents_shop/data/elite_enemy_spawn.tres")

func init(p_wave_timer:Timer, wave_data:Resource) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.init(p_wave_timer, wave_data)
		return
	
	.init(p_wave_timer, wave_data)
	var game_controller = $"/root/GameController"
	
	# Normal Game effects translated for co-op
	for player_id in game_controller.tracked_players:
		var run_data = game_controller.tracked_players[player_id].run_data
		
		if run_data.effects["extra_enemies_next_wave"] > 0:
			for i in run_data.effects["extra_enemies_next_wave"]:
				for group in extra_groups:
					current_wave_data.groups_data.push_back(group)
			run_data.effects["extra_enemies_next_wave"] = 0
			
		if run_data.effects["extra_loot_aliens_next_wave"] > 0:
			for i in run_data.effects["extra_loot_aliens_next_wave"]:
				for group in loot_alien_groups:
					var new_group = group.duplicate()
					new_group.spawn_timing = rand_range(5, wave_timer.time_left - 10)
					current_wave_data.groups_data.push_back(new_group)
			
			run_data.effects["extra_loot_aliens_next_wave"] = 0
	
	# Versus Mode Shop Options
	var extra_enemies_next_wave = game_controller.extra_enemies_next_wave
	
	if extra_enemies_next_wave.has(game_controller.self_peer_id):
		add_extra_enemies(extra_enemies_next_wave[game_controller.self_peer_id])
	
	var effects = game_controller.effects_next_wave
	if effects.has(game_controller.self_peer_id):
		var my_effects = effects[game_controller.self_peer_id]
		for effect_path in my_effects:
			for i in my_effects[effect_path]:
				load(effect_path).apply()
				
func add_extra_enemies(extra_enemies:Dictionary) -> void:
	for resource_path in extra_enemies:
		var altered_group = load(resource_path).duplicate()
		
		altered_group.repeating_interval = 1
		
		var enemy = altered_group.wave_units_data[0].unit_scene.instance()
	
		var stats = enemy.stats.duplicate()
		enemy.stats = stats
	
		enemy.stats.can_drop_consumables = false
		enemy.stats.value = 0
		 
		var altered_enemy_scene = PackedScene.new()
		altered_enemy_scene.pack(enemy)
		
		altered_group.wave_units_data[0].unit_scene = altered_enemy_scene
	
		enemy = altered_group.wave_units_data[0].unit_scene.instance()
			
		for i in extra_enemies[resource_path]:
			current_wave_data.groups_data.push_back(altered_group)
