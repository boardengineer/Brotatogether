extends "res://singletons/utils.gd"


func is_player_action_released(event: InputEvent, player_index: int, action: String)->bool:
	if CoopService.get_remapped_player_device(player_index) >= 50:
		return false
	
	return .is_player_action_released(event, player_index, action)
