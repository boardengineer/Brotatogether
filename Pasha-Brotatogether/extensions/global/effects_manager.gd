extends EffectsManager

onready var game_controller = $"/root/GameController"

func play_hit_particles(effect_pos:Vector2, direction:Vector2, effect_scale:float)->void :
	if game_controller and game_controller.is_host:
		var rpc_data = {}
		rpc_data["position"] = effect_pos
		rpc_data["direction"] = direction
		rpc_data["scale"] = effect_scale
		game_controller.send_display_hit_effect(rpc_data)
	
	.play_hit_particles(effect_pos, direction, effect_scale)
