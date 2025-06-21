extends "res://ui/menus/pages/main_menu.gd"


var multiplayer_button: Button

# Add a multiplayer button to the main menu
func _ready():
	RunData.init_multiplayer()
	SoundManager.init_multiplayer()
	SoundManager2D.init_multiplayer()
	
	var buttons_node = $"MarginContainer/VBoxContainer/HBoxContainer/ButtonsLeft"

	# Duplicate a Button to get the styling
	multiplayer_button = start_button.duplicate()
	multiplayer_button.text = "Multiplayer"
	multiplayer_button.name = "MultiplayerButton"

	var _unused = multiplayer_button.connect("pressed", self, "_on_MultiplayerButton_pressed")
	multiplayer_button.disconnect("pressed", self, "_on_StartButton_pressed")

	buttons_node.add_child_below_node(buttons_node.get_children()[0], multiplayer_button)
	buttons_node.move_child(multiplayer_button, 0)

	remove_game_controller()
	
	$"/root/BrotogetherOptions".joining_multiplayer_lobby = false
	

func init() -> void:
	.init()
	if continue_button.visible:
		continue_button.focus_neighbour_top = multiplayer_button.get_path()
	else:
		start_button.focus_neighbour_top = multiplayer_button.get_path()


func _on_MultiplayerButton_pressed():
	var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_menu.tscn")

func remove_game_controller():
	if $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		$"/root".remove_child(game_controller)
