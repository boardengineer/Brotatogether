extends FloatingTextManager

func display(value:String, text_pos:Vector2, color:Color = Color.white, icon:Resource = null, p_duration:float = duration, always_display:bool = false, p_direction:Vector2 = direction)->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.is_source_of_truth:
			var rpc_data = {}
			rpc_data["value"] = value
			rpc_data["position"] = text_pos
			rpc_data["color"] = color
			game_controller.send_display_floating_text(rpc_data)
	
	.display(value, text_pos, color, icon, p_duration, always_display, p_direction)
	
func on_stat_added(stat:String, value:int, db_mod:float = 0.0, pos_sounds:Array = stat_pos_sounds, neg_sounds:Array = stat_neg_sounds)->void :	if  $"/root".has_node("GameController"):
	if  $"/root".has_node("GameController"):
		# TODO this prevents icons from popping up because slients don't track
		# their player
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
			return
	.on_stat_added(stat, value, db_mod, pos_sounds, neg_sounds)
