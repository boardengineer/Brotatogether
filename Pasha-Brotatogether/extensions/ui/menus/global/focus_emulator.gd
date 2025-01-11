extends "res://ui/menus/global/focus_emulator.gd"

var global_focused_control


func ready() -> void:
	var _err = get_viewport().connect("gui_focus_changed", self, "_on_focus_changed_multiplayer")


func _on_focus_changed_multiplayer(control:Control) -> void:
	if control != null:
		global_focused_control = control


# Have line edit eat inputs so that you can send messages
func _handle_input(event:InputEvent) -> bool:
	if global_focused_control != null and global_focused_control is LineEdit:
		return false
	return ._handle_input(event)


func _get_focus_neighbour_for_event(event: InputEvent, target: Control)->GetFocusNeighbourForEventResult:
	if _device >= 50:
		return GetFocusNeighbourForEventResult.new()
	
	return ._get_focus_neighbour_for_event(event,target)
