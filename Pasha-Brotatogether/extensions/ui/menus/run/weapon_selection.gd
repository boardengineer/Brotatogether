extends WeaponSelection

func on_element_pressed(element:InventoryElement) -> void:
	if not $"/root".has_node("GameController"):
		.on_element_pressed(element)
		return
	
	if weapon_added:
		return 
	
	var item
	if element.is_random:
		weapon_added = true
		item = Utils.get_rand_element(available_elements)
		var _weapon = RunData.add_weapon(item, true)
	elif element.is_special:
		return 
	else :
		weapon_added = true
		item = element.item
		var _weapon = RunData.add_weapon(item, true)
	
	RunData.add_starting_items_and_weapons()
	
	if $"/root/GameController":
		var game_controller = $"/root/GameController"
		if game_controller.back_to_lobby:
			game_controller.on_weapon_selected(item.my_id)
			var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_lobby.tscn")
			return
	
	var _error = get_tree().change_scene(MenuData.difficulty_selection_scene)
