extends "res://ui/menus/ingame/pause_menu.gd"

func pause() -> void:
#	Pausing is disabled in both versus and coop
	if not $"/root".has_node("GameController"):
		.pause()
		return
	
	var game_controller = $"/root/GameController"
	if game_controller.disable_pause:
		return
	
	.pause()
