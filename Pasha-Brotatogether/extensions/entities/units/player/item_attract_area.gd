extends "res://entities/units/player/item_attract_area.gd"


func get_overlapping_areas()->Array :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return .get_overlapping_areas()
	
	var game_controller = $"/root/GameController"
	print_debug(get_parent())
	var run_data = game_controller.tracked_players[get_parent().player_network_id].run_data
	var pickup_range = run_data.effects["pickup_range"]
	
	$CollisionShape2D.shape.radius = max(30, BASE_RADIUS * (1.0 + (pickup_range / 100.0)))
	return []
