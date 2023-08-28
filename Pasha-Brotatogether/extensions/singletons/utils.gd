extends "res://singletons/utils.gd"

func get_stat(stat_name:String) -> float:
	if not $"/root".has_node("GameController"):
		return .get_stat(stat_name)
	
	if stat_name.begins_with("enemy"):
		var sum = 0.0
		var game_controller = $"/root/GameController"
		var multiplayer_utils = $"/root/MultiplayerUtils"
		
		for player_id in game_controller.tracked_players:
			sum += multiplayer_utils.get_stat_multiplayer(player_id, stat_name)
		
		return sum
	
	if stat_name == "stat_luck":
		var sum = 0.0
		var count = 0
		
		var game_controller = $"/root/GameController"
		var multiplayer_utils = $"/root/MultiplayerUtils"
		
		for player_id in game_controller.tracked_players:
			sum += multiplayer_utils.get_stat_multiplayer(player_id, stat_name)
			count += 1
			
		return sum / count

	return .get_stat(stat_name)
