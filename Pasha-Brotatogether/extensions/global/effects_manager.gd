extends EffectsManager

func play_hit_particles(effect_pos:Vector2, direction:Vector2, effect_scale:float) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.play_hit_particles(effect_pos, direction, effect_scale)
		return
	
	var game_controller = $"/root/GameController"
	if game_controller.is_host:
		game_controller.send_display_hit_effect(effect_pos, direction, effect_scale)
	
	.play_hit_particles(effect_pos, direction, effect_scale)
