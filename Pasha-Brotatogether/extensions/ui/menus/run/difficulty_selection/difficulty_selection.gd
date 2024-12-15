extends "res://ui/menus/run/difficulty_selection/difficulty_selection.gd"

var steam_connection
var brotatogether_options
var is_multiplayer_lobby = false

var inventory_by_string_key : Dictionary


func _ready():
	steam_connection = $"/root/SteamConnection"
	steam_connection.connect("difficulty_lobby_update", self, "_lobby_difficulty_updated")
	
	if is_multiplayer_lobby:
		for difficulty_data in ItemService.difficulties:
			inventory_by_string_key[difficulty_item_to_string(difficulty_data)] = difficulty_data


func difficulty_item_to_string(item : Resource) -> String:
	if item == null:
		return "RANDOM"
	return item.name


func _lobby_difficulty_updated(focused_difficulty) -> void:
	pass


func _on_element_focused(element:InventoryElement, inventory_player_index:int) -> void:
	# Disregard difficulty updates from clients
	if is_multiplayer_lobby:
		if not steam_connection.is_host():
			return
	
	._on_element_focused(element, inventory_player_index)
	
	if is_multiplayer_lobby:
		var element_string = ""
		if element.item != null:
			element_string = element.item.name
		elif element.is_random:
			element_string = "RANDOM"
		
		steam_connection.difficulty_focused(element_string)


func _focus_difficulty(difficutly : String) -> void:
	var selected_item = null
	if inventory_by_string_key.has(difficutly):
		selected_item = inventory_by_string_key[difficutly]
	_display_element_panel_data(selected_item, 0)
