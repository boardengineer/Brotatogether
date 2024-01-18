extends WeaponSelection

func on_element_pressed(element:InventoryElement)->void :
	if weapon_added:
		return 
	
	if element.is_random:
		weapon_added = true
		var _weapon = RunData.add_weapon(Utils.get_rand_element(available_elements), true)
	elif element.is_special:
		return 
	else :
		weapon_added = true
		var _weapon = RunData.add_weapon(element.item, true)
	
	RunData.add_starting_items_and_weapons()
	
	if $"/root/GameController":
		var game_controller = $"/root/GameController"
		if game_controller.back_to_lobby:
			game_controller.on_weapon_selected(element.item.my_id)
			var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_lobby.tscn")
			return
	
	var _error = get_tree().change_scene(MenuData.difficulty_selection_scene)
