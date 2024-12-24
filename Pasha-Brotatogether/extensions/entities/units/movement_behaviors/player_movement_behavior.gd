extends "res://entities/units/movement_behaviors/player_movement_behavior.gd"


func get_movement()->Vector2:
	if device >= 50:
		return Vector2.ZERO
	
	return .get_movement()
