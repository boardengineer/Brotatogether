extends CharacterSelection


func on_element_pressed(element:InventoryElement)->void :
	if not $"/root".has_node("GameController"):
		.on_element_pressed(element)
		return
	
	if character_added:
		return 
	
	var item
	if element.is_random:
		character_added = true
		item = Utils.get_rand_element(available_elements)
		RunData.add_character(item)
	elif element.is_special:
		return 
	else :
		character_added = true
		item = element.item
		RunData.add_character(element.item)
		
		
	if $"/root/GameController":
		var game_controller = $"/root/GameController"
		if game_controller.back_to_lobby:
			game_controller.on_character_selected(item.my_id)
			var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_lobby.tscn")
			return
	
	if RunData.effects["weapon_slot"] == 0:
		var _error = get_tree().change_scene(MenuData.difficulty_selection_scene)
	else :
		var _error = get_tree().change_scene(MenuData.weapon_selection_scene)
