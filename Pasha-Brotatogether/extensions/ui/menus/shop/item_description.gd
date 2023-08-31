extends "res://ui/menus/shop/item_description.gd"

func set_item(item_data:ItemParentData) -> void:
	if not $"/root".has_node("GameController"):
		.set_item(item_data)
		return
		
	var game_controller = $"/root/GameController"
	
	if not game_controller.tracked_players.has(game_controller.self_peer_id) or not game_controller.tracked_players[game_controller.self_peer_id].has("run_data"):
		.set_item(item_data)
		return
	
	get_effects().show()
	if item_data is WeaponData:
		get_weapon_stats().show()
		get_weapon_stats().bbcode_text = get_weapon_stats_text_for_weapon_data(game_controller.self_peer_id, item_data)
		_category.text = tr(ItemService.get_weapon_sets_text(item_data.sets))
	else :
		get_weapon_stats().hide()
		if item_data is CharacterData:
			_category.text = tr("CHARACTER")
		elif item_data is UpgradeData:
			_category.text = tr("UPGRADE")
		elif item_data is DifficultyData:
			_category.text = tr("DIFFICULTY")
		else :
			if item_data.max_nb == 1:
				_category.text = tr("UNIQUE")
			elif item_data.max_nb != - 1:
				_category.text = Text.text("LIMITED", [str(item_data.max_nb)])
			else :
				_category.text = tr("ITEM")
	
	if item_data is WeaponData or item_data is UpgradeData:
		var tier_number = ItemService.get_tier_number(item_data.tier)
		_name.text = tr(item_data.name) + (" " + tier_number if tier_number != "" else "")
	elif item_data is DifficultyData:
		_name.text = Text.text(tr(item_data.name), [str(item_data.value)])
	else :
		_name.text = item_data.name
	
	item = item_data
	_icon.texture = item_data.icon
	_name.modulate = ItemService.get_color_from_tier(item_data.tier)
	
	if item_data is DifficultyData and item_data.effects.size() == 0:
		get_effects().bbcode_text = item_data.description
	else :
		print_debug("code ", item_data.get_effects_text())
		get_effects().bbcode_text = item_data.get_effects_text()

func get_weapon_stats_text_for_weapon_data(player_id:int, item_data:ItemParentData)->String:
	var current_stats
	
	var multiplayer_weapon_service = $"/root/MultiplayerWeaponService"
	
	if item_data.type == WeaponData.Type.MELEE:
		current_stats = multiplayer_weapon_service.init_melee_stats_multiplayer(player_id, item_data.stats, item_data.weapon_id, item_data.sets, item_data.effects)
	else :
		current_stats = multiplayer_weapon_service.init_ranged_stats_multiplayer(player_id, item_data.stats, item_data.weapon_id, item_data.sets, item_data.effects)
	
	return current_stats.get_text(item_data.stats)
