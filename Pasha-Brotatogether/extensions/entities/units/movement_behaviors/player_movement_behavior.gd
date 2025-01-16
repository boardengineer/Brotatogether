extends "res://entities/units/movement_behaviors/player_movement_behavior.gd"


func get_movement()->Vector2:
	if device >= 50:
		return get_parent()._current_movement
	
	return .get_movement()
