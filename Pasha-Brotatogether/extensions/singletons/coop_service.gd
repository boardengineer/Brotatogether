extends "res://singletons/coop_service.gd"


func is_player_using_gamepad(player_index) -> bool:
	if get_remapped_player_device(player_index) >= 50:
		return false
	
	return .is_player_using_gamepad(player_index)
