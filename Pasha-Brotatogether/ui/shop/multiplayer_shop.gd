extends Shop

func _ready():
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return
		
	var game_controller = $"/root/GameController"
	
	if game_controller.is_host:
		game_controller.receive_player_enter_shop(game_controller.self_peer_id)
	else:
		game_controller.send_client_entered_shop()
		yield(game_controller, "complete_player_update")
	
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
	var label_text = tr("WEAPONS") + " (" + str(run_data.weapons.size()) + "/" + str(run_data.effects["weapon_slot"]) + ")"

	_stats_container.update_stats()	
	_weapons_container.set_data(label_text, Category.WEAPON, run_data.weapons)
	_items_container.set_data("ITEMS", Category.ITEM, run_data.items, true, true)
	_gold_label.update_gold(run_data.gold)
	_initial_free_rerolls = run_data.effects["free_rerolls"]
	_free_rerolls = _initial_free_rerolls
	set_reroll_button_price()

func on_shop_item_bought(shop_item:ShopItem) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.on_shop_item_bought(shop_item)
		return
	
	var game_controller = $"/root/GameController"
	
	emit_signal("item_bought", shop_item.item_data)
	game_controller.send_bought_item_by_id(shop_item.item_data.my_id, shop_item.value)
	
	if not game_controller.is_host:
		game_controller.send_complete_player_request()
		yield(game_controller, "complete_player_update")
			
	_stats_container.update_stats()
	_shop_items_container.reload_shop_items_descriptions()
#	This lack of removal probably has some problems
#	for item in _shop_items:
#		if item[0].my_id == shop_item.item_data.my_id:
#			_shop_items.erase(item)
#			break
		
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
	var label_text = tr("WEAPONS") + " (" + str(run_data.weapons.size()) + "/" + str(run_data.effects["weapon_slot"]) + ")"
		
	_weapons_container.set_label(label_text)
		
	print_debug("emitting signal")
	RunData.emit_signal("gold_changed", run_data.gold)
	_shop_items_container.update_buttons_color()
	
	var has_new_rerolls = false
	
	if run_data.effects["free_rerolls"] > _initial_free_rerolls:
		var new_rerolls = run_data.effects["free_rerolls"] - _initial_free_rerolls
		_initial_free_rerolls = run_data.effects["free_rerolls"]
		_free_rerolls += new_rerolls
		has_new_rerolls = true
	
	if _shop_items.size() == 0:
		
		if _reroll_price == 0:
			_free_rerolls += 1
		
		_free_rerolls += 1
		has_new_rerolls = true
		
	if has_new_rerolls:
		set_reroll_button_price()
	else :
		_reroll_button.set_color_from_currency(run_data.gold)

func on_item_combine_button_pressed(weapon_data:WeaponData, is_upgrade:bool = false)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.on_item_combine_button_pressed(weapon_data, is_upgrade)
		return
		
	var game_controller = $"/root/GameController"
	game_controller.on_item_combine_button_pressed(weapon_data, is_upgrade)
	
	if not game_controller.is_host:
		game_controller.send_complete_player_request()
		yield(game_controller, "complete_player_update")
		
		var nb_to_remove = 2
		
		if is_upgrade:
			nb_to_remove = 1
		
		_weapons_container._elements.remove_element(weapon_data, nb_to_remove)
		
		var weapons = game_controller.tracked_players[game_controller.self_peer_id].run_data.weapons
		var new_weapon = weapons[weapons.size() - 1]
		
		_weapons_container._elements.add_element(new_weapon)
		
		reset_item_popup_focus()
		
	_focus_manager.reset_focus()

func on_item_discard_button_pressed(weapon_data:WeaponData)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.on_item_discard_button_pressed(weapon_data)
		return

	_focus_manager.reset_focus()
	
	var game_controller = $"/root/GameController"
	game_controller.on_item_discard_button_pressed(weapon_data)
	
	
	if not game_controller.is_host:
		yield(game_controller, "complete_player_update")
	
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
		
	_weapons_container._elements.remove_element(weapon_data)
	reset_item_popup_focus()
	_shop_items_container.update_buttons_color()
	_reroll_button.set_color_from_currency(run_data.gold)
	SoundManager.play(Utils.get_rand_element(recycle_sounds), 0, 0.1, true)

func _on_RerollButton_pressed()->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
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
