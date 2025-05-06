extends "res://global/effects_manager.gd"

var steam_connection
var brotatogether_options
var in_multiplayer_game = false
var is_host = false


func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"
	in_multiplayer_game = brotatogether_options.in_multiplayer_game
	
	if in_multiplayer_game:
		is_host = steam_connection.is_host()


func play_hit_particles(effect_pos: Vector2, direction: Vector2, effect_scale: float) -> void:
	.play_hit_particles(effect_pos, direction, effect_scale)
	
	if in_multiplayer_game and self.is_host:
		var hit_particle_dict = {}
		hit_particle_dict["X_POS"] = effect_pos.x
		hit_particle_dict["Y_POS"] = effect_pos.y
		hit_particle_dict["X_DIR"] = direction.x
		hit_particle_dict["Y_DIR"] = direction.y
		hit_particle_dict["SCALE"] = effect_scale
		brotatogether_options.batched_hit_particles.push_back(hit_particle_dict)


func play_hit_effect(effect_pos: Vector2, _direction: Vector2, effect_scale: float)->void :
	.play_hit_effect(effect_pos, _direction, effect_scale)
	
	if in_multiplayer_game and self.is_host:
		var hit_effect_dict = {}
		hit_effect_dict["X_POS"] = effect_pos.x
		hit_effect_dict["Y_POS"] = effect_pos.y
		hit_effect_dict["SCALE"] = effect_scale
		brotatogether_options.batched_hit_effects.push_back(hit_effect_dict)
