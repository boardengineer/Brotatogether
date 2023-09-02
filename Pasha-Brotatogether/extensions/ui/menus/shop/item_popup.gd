extends "res://ui/menus/shop/item_popup.gd"

func display_element(element:InventoryElement) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.display_element(element)
		return
		
	.display_element(element)
	
	var run_data_node = $"/root/MultiplayerRunData"
	var game_controller = $"/root/GameController"
	
	if element.item is WeaponData and buttons_active:
		if run_data_node.can_combine_multiplayer(game_controller.self_peer_id, element.item):
			_combine_button.show()
			
#	show()
