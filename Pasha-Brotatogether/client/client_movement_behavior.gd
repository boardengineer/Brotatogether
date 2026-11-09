extends MovementBehavior

signal detected_player

# Read/written by 1.2 boss scripts (Brachiosaurus._physics_process) on their movement behavior.
var should_follow_player = false

func init(parent:Node)->Node:
	var _init = .init(parent)
	return self


func get_movement()->Vector2:
	return Vector2.ZERO


# Enemy scripts call these on their own (replaced) movement behavior; on a client the host
# drives the position, so they do nothing. 1.2 bosses added the last two
# (Brachiosaurus.on_state_changed, BrachiosaurusFoot._ready).
func set_detected(_is_detected: bool) -> void:
	pass


func add_lung(_lung) -> void:
	pass


func get_new_target() -> Vector2:
	return _parent.global_position if is_instance_valid(_parent) else Vector2.ZERO


func move_to_new_edge() -> void:
	pass


func move_away() -> void:
	pass
