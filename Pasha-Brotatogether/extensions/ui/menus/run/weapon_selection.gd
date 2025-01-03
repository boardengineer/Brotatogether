extends "res://ui/menus/run/weapon_selection.gd"

var steam_connection
var brotatogether_options
var is_multiplayer_lobby = false

var inventory_by_string_key : Dictionary

func _ready():
	steam_connection = $"/root/SteamConnection"
	
	steam_connection.connect("player_focused_weapon", self, "_player_focused_weapon")
	steam_connection.connect("player_selected_weapon", self, "_player_selected_weapon")
	steam_connection.connect("weapon_lobby_update", self, "_lobby_weapons_updated")
	
	
	brotatogether_options = $"/root/BrotogetherOptions"
	is_multiplayer_lobby = brotatogether_options.joining_multiplayer_lobby
	
	if is_multiplayer_lobby:
		for weapon_data in ItemService.weapons:
			inventory_by_string_key[weapon_item_to_string(weapon_data)] = weapon_data


func weapon_item_to_string(item : Resource) -> String:
	if item == null:
		return "RANDOM"
	return item.name


func _lobby_weapons_updated(player_weapons : Array, has_player_selected : Array) -> void:
	for player_index in player_weapons.size():
		if player_weapons[player_index] != null:
			_player_focused_weapon(player_index, player_weapons[player_index])
	
	var all_selected = true
	for player_index in RunData.get_player_count():
		if has_player_selected[player_index]:
			_set_selected_element(player_index)
		else:
			all_selected = false
			_clear_selected_element(player_index)
	
	if all_selected:
		_selections_completed_timer.start()


func _on_element_focused(element:InventoryElement, inventory_player_index:int) -> void:
	._on_element_focused(element, inventory_player_index)
	
	if is_multiplayer_lobby:
		var element_string = ""
		if element.item != null:
			element_string = element.item.name
		elif element.is_random:
			element_string = "RANDOM"
		
		steam_connection.weapon_focused(element_string)


func _player_focused_weapon(player_index : int , weapon : String) -> void:
	var selected_item = null
	if inventory_by_string_key.has(weapon):
		selected_item = inventory_by_string_key[weapon]
	_player_weapons[player_index] = selected_item
	_clear_selected_element(player_index)
	
	var panel = _get_panels()[player_index]
	if panel.visible:
		# TODO handle randoms
		if selected_item != null:
			panel.set_data(selected_item, player_index)


func _player_selected_weapon(player_index : int) -> void:
	_set_selected_element(player_index)


func _set_selected_element(p_player_index:int) -> void:
	if _has_player_selected[p_player_index]:
		return
	
	._set_selected_element(p_player_index)
	
	if steam_connection.get_lobby_index_for_player(steam_connection.steam_id) == p_player_index:
		steam_connection.weapon_selected()
