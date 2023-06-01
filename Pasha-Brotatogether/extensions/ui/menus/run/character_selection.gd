extends CharacterSelection


func on_element_pressed(element:InventoryElement)->void :
	if character_added:
		return 
	
	if element.is_random:
		character_added = true
		RunData.add_character(Utils.get_rand_element(available_elements))
	elif element.is_special:
		return 
	else :
		character_added = true
		RunData.add_character(element.item)
		
		
	if $"/root/GameController":
		if $"/root/GameController".back_to_lobby:
			var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_lobby.tscn")
			return
	
	if RunData.effects["weapon_slot"] == 0:
		var _error = get_tree().change_scene(MenuData.difficulty_selection_scene)
	else :
		var _error = get_tree().change_scene(MenuData.weapon_selection_scene)
