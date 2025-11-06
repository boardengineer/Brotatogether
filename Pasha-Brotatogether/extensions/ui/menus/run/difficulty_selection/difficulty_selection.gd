extends "res://ui/menus/run/difficulty_selection/difficulty_selection.gd"

var steam_connection
var brotatogether_options
var is_multiplayer_lobby = false

var inventory_by_string_key : Dictionary


func _ready():
	steam_connection = $"/root/SteamConnection"
	steam_connection.connect("difficulty_focused", self, "_difficulty_focused")
	steam_connection.connect("difficulty_selected", self, "_difficulty_selected")
	
	brotatogether_options = $"/root/BrotogetherOptions"
	is_multiplayer_lobby = brotatogether_options.joining_multiplayer_lobby
	
	if is_multiplayer_lobby:
		brotatogether_options.joining_multiplayer_lobby = false
		brotatogether_options.in_multiplayer_game = true
		
		for difficulty_data in ItemService.difficulties:
			inventory_by_string_key[difficulty_data.value] = difficulty_data
	print_debug("created difficulty element map ", inventory_by_string_key)


func _on_element_focused(element:InventoryElement, inventory_player_index:int, _displayPanelData: bool = true) -> void:
	# Disregard difficulty updates from clients
	if is_multiplayer_lobby:
		if not steam_connection.is_host():
			return
	
	._on_element_focused(element, inventory_player_index)
	
	if is_multiplayer_lobby:
		steam_connection.difficulty_focused()


func _on_element_pressed(element: InventoryElement, _inventory_player_index: int) -> void:
	# Disregard difficulty updates from clients
	if is_multiplayer_lobby:
		if not steam_connection.is_host():
			return
	
	._on_element_pressed(element, _inventory_player_index)
	
	if is_multiplayer_lobby:
		steam_connection.difficulty_pressed()


func _difficulty_selected(difficutly : int) -> void:
	print_debug("received difficulty focus update: ", difficutly)
	var _error = get_tree().change_scene(MenuData.game_scene)


func _difficulty_focused(difficutly : int) -> void:
	print_debug("received difficulty focus update: ", difficutly)
	
	# Hosts don't respect update calls
	if is_multiplayer_lobby:
		if steam_connection.is_host():
			return
	
	var selected_item = null
	if inventory_by_string_key.has(difficutly):
		selected_item = inventory_by_string_key[difficutly]
	if selected_item != null:
		_get_panels()[0].visible = true
		_get_panels()[0].set_data(selected_item, 0)
