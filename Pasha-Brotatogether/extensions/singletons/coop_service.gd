extends "res://singletons/coop_service.gd"


func is_player_using_gamepad(player_index) -> bool:
	if get_remapped_player_device(player_index) >= 50:
		return false
	
	return .is_player_using_gamepad(player_index)


# Brotatogether registers every lobby member with player type 10 (character_selection.gd
# MULTIPLAYER_CLIENT_PLAYER_TYPE), which is not a PlayerType value. The vanilla lookup below
# matches on PlayerType, so every co-op key hint (lock [E], ban [R], item details [Space], ...)
# got a null texture and drew an empty gap. Multiplayer players play with keyboard and mouse on
# their own machine, so show the keyboard keys. Triggers still resolve to null for keyboard,
# exactly as they did for type 10, so the carousel arrows are unchanged.
const MULTIPLAYER_CLIENT_PLAYER_TYPE = 10

func get_player_key_texture(action: String, player_index: int) -> Texture:
	if player_index >= 0 and player_index < len(connected_players) and get_player_input_type(player_index) == MULTIPLAYER_CLIENT_PLAYER_TYPE:
		return get_input_type_key_texture(action, PlayerType.KEYBOARD_AND_MOUSE, 0)
	return .get_player_key_texture(action, player_index)
