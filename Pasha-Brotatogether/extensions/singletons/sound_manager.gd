extends "res://singletons/sound_manager.gd"

var steam_connection
var brotatogether_options

var is_multiplayer_lobby = false


func init_multiplayer() -> void:
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"


func play(sound: Resource, volume_mod: float = 0.0, pitch_rand: float = 0.0, always_play: bool = false)->void :
	if steam_connection and brotatogether_options:
		if brotatogether_options.in_multiplayer_game:
			if steam_connection.is_host():
				var sound_dict = {
					"RESOURCE_PATH" : sound.resource_path,
				}
				brotatogether_options.batched_sounds.push_back(sound_dict)
	.play(sound, volume_mod, pitch_rand, always_play)
