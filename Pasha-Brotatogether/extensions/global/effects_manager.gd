extends EffectsManager

func play_hit_particles(effect_pos:Vector2, direction:Vector2, effect_scale:float)->void :
	if get_tree().is_network_server():
		var rpc_data = {}
		rpc_data["position"] = effect_pos
		rpc_data["direction"] = direction
		rpc_data["scale"] = effect_scale
		$"/root/networking".rpc("display_hit_effect", rpc_data)
	
	.play_hit_particles(effect_pos, direction, effect_scale)
