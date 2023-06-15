extends "res://ui/menus/ingame/pause_menu.gd"

func pause() -> void:
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller.disable_pause:
			return
	.pause()
