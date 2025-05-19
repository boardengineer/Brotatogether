extends MovementBehavior

func init(parent:Node)->Node:
	var _init = .init(parent) 
	return self


func get_movement()->Vector2:
	return Vector2.ZERO
