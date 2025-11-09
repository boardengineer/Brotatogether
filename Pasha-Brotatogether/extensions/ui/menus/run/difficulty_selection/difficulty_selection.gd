extends "res://ui/menus/run/difficulty_selection/difficulty_selection.gd"

var steam_connection
var brotatogether_options
var is_multiplayer_lobby = false

var inventory_by_string_key : Dictionary
var selection_by_string_key : Dictionary


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
			selection_by_string_key[difficulty_data.value] = difficulty_data
		
		for inventory_item in _get_inventories()[0].get_children():
			inventory_by_string_key[inventory_item.item.value] = inventory_item


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
	var _error = get_tree().change_scene(MenuData.game_scene)


func _difficulty_focused(difficutly : int) -> void:
	
	# Hosts don't respect update calls
	if is_multiplayer_lobby:
		if steam_connection.is_host():
			return
	
	var selected_item = null
	if selection_by_string_key.has(difficutly):
		selected_item = selection_by_string_key[difficutly]
		
	Utils.get_focus_emulator(0).focused_control = inventory_by_string_key[difficutly]
		
	if selected_item != null:
		_get_panels()[0].visible = true
		_get_panels()[0].set_data(selected_item, 0)
