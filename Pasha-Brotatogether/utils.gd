extends Node

func get_stat_multiplayer(player_id:int, stat_name:String) -> float:
	return $"/root/MultiplayerRunData".get_stat(player_id, stat_name) + get_temp_stat(player_id, stat_name) + get_linked_stats(player_id, stat_name)
	
func get_temp_stat(player_id:int, stat_name:String) -> float:
	var game_controller = get_game_controller()
	
	if not game_controller:
		return 0.0
	
	var tracked_players = game_controller.tracked_players
	
	if stat_name in tracked_players[player_id]["temp_stats"]["stats"]:
		return tracked_players[player_id]["temp_stats"]["stats"][stat_name] * $"/root/MultiplayerRunData".get_stat_gain(player_id, stat_name)
	else :
		return 0.0
		
		
func get_linked_stats(player_id:int, stat_name:String) -> float:
	var game_controller = get_game_controller()
	
	if not game_controller:
		return 0.0
	
	var tracked_players = game_controller.tracked_players
	
	if stat_name in tracked_players[player_id]["linked_stats"]["stats"]:
		return tracked_players[player_id]["linked_stats"]["stats"][stat_name] * $"/root/MultiplayerRunData".get_stat_gain(player_id, stat_name)
	else :
		return 0.0
	
func get_game_controller():
	if not $"/root".has_node("GameController"):
		return null
	return $"/root/GameController"
