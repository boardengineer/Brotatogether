extends Shop

func _ready():
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		
		var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
		
		var label_text = tr("WEAPONS") + " (" + str(run_data.weapons.size()) + "/" + str(run_data.effects["weapon_slot"]) + ")"
		
		_weapons_container.set_data(label_text, Category.WEAPON, run_data.weapons)

func on_shop_item_bought(shop_item:ShopItem) -> void:
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		game_controller.send_bought_item_by_id(shop_item.item_data.my_id)
		
		var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
		
		var label_text = tr("WEAPONS") + " (" + str(run_data.weapons.size()) + "/" + str(run_data.effects["weapon_slot"]) + ")"
		
		print_debug("setting shop item text to ", label_text)
		_weapons_container.set_label(label_text)
		
		emit_signal("item_bought", shop_item.item_data)
	else:
		.on_shop_item_bought(shop_item)
