class_name PlayerTwoMovementBehavior
extends MovementBehavior

const MIN_MOVE_DIST = 20

var last_movement = Vector2.ZERO


func get_movement()->Vector2:
	var movement:Vector2 = Vector2.ZERO
	
	if ProgressData.settings.mouse_only:
		var mouse_pos = get_global_mouse_position()
		movement = Vector2(mouse_pos.x - _parent.global_position.x, mouse_pos.y - _parent.global_position.y)
		
		if (abs(movement.x) < MIN_MOVE_DIST and abs(movement.y) < MIN_MOVE_DIST) or Input.is_mouse_button_pressed(BUTTON_LEFT):
			movement = Vector2.ZERO
	else :
		if InputService.using_gamepad:
			movement = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		else :
			movement = Input.get_vector("ui_right_keyboard_only", "ui_left_keyboard_only", "ui_up_keyboard_only", "ui_down_keyboard_only")
	
	if RunData.effects["cant_stop_moving"] and movement == Vector2.ZERO:
		if last_movement == Vector2.ZERO:
			movement = Vector2(rand_range( - PI, PI), rand_range( - PI, PI))
		else :
			movement = last_movement
	
	last_movement = movement
	
	return movement
