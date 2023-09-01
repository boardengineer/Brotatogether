extends "res://ui/menus/run/end_run.gd"

func _ready():
	if not $"/root".has_node("GameController"):
		return
	
	var game_controller = $"/root/GameController"
	
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
	
	_items_container.set_data("ITEMS", Category.ITEM, run_data.items, true, true)
	_weapons_container.set_data("WEAPONS", Category.WEAPON, run_data.weapons)
	
	_new_run_button.hide()
	_retry_button.hide()
