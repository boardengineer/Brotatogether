extends "res://singletons/utils.gd"

func get_stat(stat_name:String) -> float:
	if not $"/root".has_node("GameController"):
		return .get_stat(stat_name)
	
	var sum = 0.0
	if stat_name.begins_with("enemy"):
		var game_controller = $"/root/GameController"
		var multiplayer_utils = $"/root/MultiplayerUtils"
		
		for player_id in game_controller.tracked_players:
			sum += multiplayer_utils.get_stat_multiplayer(player_id, stat_name)
			
	print_debug("returning sum ", sum)
	return sum
