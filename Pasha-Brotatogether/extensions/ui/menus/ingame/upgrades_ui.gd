extends "res://ui/menus/ingame/upgrades_ui.gd"

func _on_RerollButton_pressed()->void :
	if not $"/root".has_node("GameController"):
		._on_RerollButton_pressed()
		return
	
	var game_controller = $"/root/GameController"
	game_controller.reroll_upgrades()
	
	if not game_controller.is_host:
		yield(game_controller, "complete_player_update")
		
		_reroll_price = ItemService.get_reroll_price(RunData.current_wave, _reroll_price)
		show_upgrade_options(_level)
