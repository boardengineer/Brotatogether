extends "res://ui/menus/pages/main_menu.gd"

# Add a multiplayer button to the main menu
func _ready():
	var buttons_node = $"HBoxContainer/ButtonsLeft"
	
	# Duplicate a Button to get the styling
	var multiplayer_button = start_button.duplicate()
	multiplayer_button.text = "Multiplayer"
	
	multiplayer_button.connect("pressed", self, "_on_MultiplayerButton_pressed")
	multiplayer_button.disconnect("pressed", self, "_on_StartButton_pressed")
	
	buttons_node.add_child_below_node(buttons_node.get_children()[0], multiplayer_button)
	buttons_node.move_child(multiplayer_button, 0)

func _on_MultiplayerButton_pressed():
	var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/extensions/ui/menus/pages/multiplayer_menu.tscn")
