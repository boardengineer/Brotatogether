extends "res://ui/menus/shop/shop_item.gd"

func update_color()->void :
	if not $"/root".has_node("GameController"):
		.update_color()
		return
	
	var game_controller = $"/root/GameController"
	var run_data_node = $"/root/MultiplayerRunData"
		
	_button.set_color_from_currency(run_data_node.get_currency(game_controller.self_peer_id))

func set_shop_item(p_item_data:ItemParentData, p_wave_value:int = RunData.current_wave)->void :
	if not $"/root".has_node("GameController"):
		.set_shop_item(p_item_data, p_wave_value)
		return
	
	activate()
	
	var run_data_node = $"/root/MultiplayerRunData"
	var game_controller = $"/root/GameController"

	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
	
	item_data = p_item_data
	_item_description.set_item(p_item_data)
	wave_value = p_wave_value
	value = ItemService.get_value(wave_value, p_item_data.value, true, p_item_data is WeaponData, p_item_data.my_id)
	
	var icon = ItemService.material_icon.get_data()
	var texture = ImageTexture.new()
	var color = Utils.GOLD_COLOR
	
	if run_data.effects["hp_shop"]:
		value = ceil(value / 20.0) as int
		icon = ItemService.get_stat_icon("stat_max_hp").get_data()
		icon.resize(64, 64)
		color = Color.white
	
	if run_data.current_character != null and run_data.current_character.my_id == "character_renegade" and item_data is ItemData and item_data.tier == Tier.COMMON:
		
		var already_has_item = false
		
		for item in run_data.items:
			if item.my_id == item_data.my_id:
				already_has_item = true
				break
		
		if not already_has_item:
			icon = run_data.current_character.icon.get_data()
			icon.resize(52, 52)
			texture = ImageTexture.new()
			texture.create_from_image(icon)
			color = Color.white
	
	texture.create_from_image(icon)
	_button.set_icon(texture, color)
	_button.set_value(value, run_data_node.get_currency(game_controller.self_peer_id))
	
	if not locked:
		var stylebox_color = _panel.get_stylebox("panel").duplicate()
		ItemService.change_panel_stylebox_from_tier(stylebox_color, p_item_data.tier)
		_panel.add_stylebox_override("panel", stylebox_color)
