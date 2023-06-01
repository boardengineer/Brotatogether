extends DifficultySelection


func on_element_pressed(element:InventoryElement)->void :
	if element.is_special:
		return 
	else :
		difficulty_selected = true
		
		var character_difficulty = ProgressData.get_character_difficulty_info(RunData.current_character.my_id, RunData.current_zone)
		
		character_difficulty.difficulty_selected_value = element.item.value
		
		RunData.init_elites_spawn()
		
		ProgressData.save()
		
		for effect in element.item.effects:
			effect.apply()
	
	MusicManager.tween(0)
	RunData.current_run_accessibility_settings = ProgressData.settings.enemy_scaling.duplicate()
	ProgressData.save_status = SaveStatus.SAVE_OK
	
	if $"/root/GameController":
		if $"/root/GameController".back_to_lobby:
			get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_lobby.tscn")
			return
			
	var _error = get_tree().change_scene(MenuData.game_scene)

func get_elements_unlocked()->Array:
	var unlocked_difficulties = []
	
	for diff in ItemService.difficulties:
#		var max_diff = ProgressData.get_character_difficulty_info(RunData.current_character.my_id, RunData.current_zone).max_selectable_difficulty
		var max_diff = 5
		if diff.value <= max_diff or diff.unlocked_by_default or DebugService.unlock_all_difficulties:
			unlocked_difficulties.push_back(diff.my_id)
	
	return unlocked_difficulties
