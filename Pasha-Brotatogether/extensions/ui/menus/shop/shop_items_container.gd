extends "res://ui/menus/shop/shop_items_container.gd"

func on_shop_item_buy_button_pressed(shop_item:ShopItem)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.on_shop_item_buy_button_pressed(shop_item)
		return
	
	var game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
	var run_data_node = $"/root/MultiplayerRunData"
	var player_id = game_controller.self_peer_id
			
	if run_data_node.get_currency(player_id) < shop_item.value or _is_delay_active:
		return 
	
	var player_has_weapon = false
	
	for weapon in run_data.weapons:
		if weapon.my_id == shop_item.item_data.my_id:
			player_has_weapon = true
			break
	
	if (shop_item.item_data.get_category() == Category.WEAPON
		 and not run_data_node.has_weapon_slot_available(player_id, shop_item.item_data.type)
		 and (
			 not player_has_weapon
			 or shop_item.item_data.upgrades_into == null
			 or (run_data.effects["max_weapon_tier"] < shop_item.item_data.upgrades_into.tier)
			)
		):
		return 
	
	if (shop_item.item_data.get_category() == Category.WEAPON
		 and (
			(shop_item.item_data.type == WeaponType.MELEE and run_data.effects["no_melee_weapons"])
			 or 
			(shop_item.item_data.type == WeaponType.RANGED and run_data.effects["no_ranged_weapons"])
			 or 
			(run_data.effects["min_weapon_tier"] > shop_item.item_data.tier)
			 or 
			(run_data.effects["max_weapon_tier"] < shop_item.item_data.tier)
		)):
			return 
	
	emit_signal("shop_item_bought", shop_item)
	shop_item.deactivate()
	
	update_buttons_color()
	
	_is_delay_active = true
	_buy_delay_timer.start()
