extends Shop

func _ready():
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		
		var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
		
		var label_text = tr("WEAPONS") + " (" + str(run_data.weapons.size()) + "/" + str(run_data.effects["weapon_slot"]) + ")"
		
		_weapons_container.set_data(label_text, Category.WEAPON, run_data.weapons)
		_items_container.set_data("ITEMS", Category.ITEM, run_data.items, true, true)
		
		_gold_label.update_gold(run_data.gold)

func on_shop_item_bought(shop_item:ShopItem) -> void:
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		game_controller.send_bought_item_by_id(shop_item.item_data.my_id, shop_item.value)
	
		if not game_controller.is_host:
			game_controller.send_complete_player_request()
			yield(game_controller, "complete_player_update")
#		This lack of removal probably has some problems
#		for item in _shop_items:
#			if item[0].my_id == shop_item.item_data.my_id:
#				_shop_items.erase(item)
#				break
		
		var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
		
		var label_text = tr("WEAPONS") + " (" + str(run_data.weapons.size()) + "/" + str(run_data.effects["weapon_slot"]) + ")"
		
		_weapons_container.set_label(label_text)
		
		emit_signal("item_bought", shop_item.item_data)
		RunData.emit_signal("gold_changed", run_data.gold)
		_shop_items_container.update_buttons_color()
	else:
		.on_shop_item_bought(shop_item)

func on_item_combine_button_pressed(weapon_data:WeaponData, is_upgrade:bool = false)->void :
	if not $"/root".has_node("GameController"):
		.on_item_combine_button_pressed(weapon_data, is_upgrade)
		return

	_focus_manager.reset_focus()
	
	var game_controller = $"/root/GameController"
	game_controller.on_item_combine_button_pressed(weapon_data, is_upgrade)
	
	game_controller.send_complete_player_request()
	yield(game_controller, "complete_player_update")

func on_item_discard_button_pressed(weapon_data:WeaponData)->void :
	if not $"/root".has_node("GameController"):
		.on_item_discard_button_pressed(weapon_data)
		return

	_focus_manager.reset_focus()
	
	var game_controller = $"/root/GameController"
	game_controller.on_item_discard_button_pressed(weapon_data)

func _on_RerollButton_pressed()->void :
	if not $"/root".has_node("GameController"):
		._on_RerollButton_pressed()
		return
		
	var game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
	var run_data_node = $"/root/MultiplayerRunData"
	
	if run_data.gold >= _reroll_price and RunData.locked_shop_items.size() < ItemService.NB_SHOP_ITEMS:
		run_data_node.remove_gold(game_controller.self_peer_id, _reroll_price)
		
		if RunData.locked_shop_items.size() > 0:
			fill_shop_items_when_locked(RunData.locked_shop_items)
		else :
			_shop_items = ItemService.get_shop_items(RunData.current_wave, ItemService.NB_SHOP_ITEMS, _shop_items)
		
		_shop_items_container.set_shop_items(_shop_items)
		
		for i in RunData.locked_shop_items.size():
			_shop_items_container.lock_shop_item_visually(i)
		
		set_reroll_button_price()
		
		_shop_items_container.update_buttons_color()
