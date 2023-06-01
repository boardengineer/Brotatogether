extends WaveManager

#var test_group = preload("res://mods-unpacked/Pasha-Brotatogether/opponents_shop/data/elite_enemy_spawn.tres")

func init(p_wave_timer:Timer, wave_data:Resource)->void :
	.init(p_wave_timer, wave_data)
	
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		var extra_enemies_next_wave = game_controller.extra_enemies_next_wave
		
		if not extra_enemies_next_wave.has(game_controller.self_peer_id):
			return
			
		# The rest of this logic will be more interesting when this gets more
		# complicated.
		var extra_enemies = extra_enemies_next_wave[game_controller.self_peer_id]
		
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
