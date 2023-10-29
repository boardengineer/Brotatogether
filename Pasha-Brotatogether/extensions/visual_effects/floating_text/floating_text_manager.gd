extends FloatingTextManager

func display(value:String, text_pos:Vector2, color:Color = Color.white, icon:Resource = null, p_duration:float = duration, always_display:bool = false, p_direction:Vector2 = direction)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.display(value, text_pos, color, icon, p_duration, always_display, p_direction)
		return
		
	var game_controller = $"/root/GameController"
	if game_controller.is_host:
		game_controller.send_display_floating_text(value, text_pos, color)
	
	.display(value, text_pos, color, icon, p_duration, always_display, p_direction)
	
func on_stat_added(stat:String, value:int, db_mod:float = 0.0, pos_sounds:Array = stat_pos_sounds, neg_sounds:Array = stat_neg_sounds)->void :	
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.on_stat_added(stat, value, db_mod, pos_sounds, neg_sounds)
		return
	
	# TODO this prevents icons from popping up because slients don't track
	# their player
	var game_controller = $"/root/GameController"
	if game_controller.is_host:
		.on_stat_added(stat, value, db_mod, pos_sounds, neg_sounds)
	
func on_gold_picked_up_multiplayer(gold:Node, _player_id) -> void:
	.on_gold_picked_up(gold)
