extends "res://ui/menus/run/weapon_selection.gd"

var steam_connection
var brotatogether_options
var is_multiplayer_lobby = false

var selections_by_string_key : Dictionary
var external_focus = false


var inventory_maps : Array

func _ready():
	steam_connection = $"/root/SteamConnection"
	
	steam_connection.connect("player_focused_weapon", self, "_player_focused_weapon")
	steam_connection.connect("player_selected_weapon", self, "_player_selected_weapon")
	steam_connection.connect("weapon_lobby_update", self, "_lobby_weapons_updated")
	steam_connection.connect("weapon_selection_completed", self, "_weapon_selection_completed")
	
	brotatogether_options = $"/root/BrotogetherOptions"
	is_multiplayer_lobby = brotatogether_options.joining_multiplayer_lobby
	
	if is_multiplayer_lobby:
		for weapon_data in ItemService.weapons:
			selections_by_string_key[weapon_item_to_string(weapon_data)] = weapon_data
	
	inventory_maps = []
	for player_index in RunData.get_player_count():
		var inventory_map = {}
		for inventory_item in _get_inventories()[player_index].get_children():
			inventory_map[weapon_item_to_string(inventory_item.item)] = inventory_item
		inventory_maps.push_back(inventory_map)


func weapon_item_to_string(item : Resource) -> String:
	if item == null:
		return "RANDOM"
	return item.my_id


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


func _on_element_focused(element:InventoryElement, inventory_player_index:int, _displayPanelData: bool = true) -> void:
	._on_element_focused(element, inventory_player_index)
	
	if is_multiplayer_lobby:
		var element_string = ""
		if element.item != null:
			element_string = element.item.my_id
		elif element.is_random:
			element_string = "RANDOM"
		
		if not external_focus:
			steam_connection.weapon_focused(element_string)
		else:
			external_focus = false


func _player_focused_weapon(player_index : int , weapon : String) -> void:
	var selected_item = null
	if selections_by_string_key.has(weapon):
		selected_item = selections_by_string_key[weapon]
		
	var focused_weapon = null
	if inventory_maps[player_index].has(weapon):
		focused_weapon = inventory_maps[player_index][weapon]
	
	if focused_weapon != null:
			if Utils.get_focus_emulator(player_index).focused_control != focused_weapon:
				external_focus = true
				Utils.get_focus_emulator(player_index).focused_control = focused_weapon
	
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
	
	# This happens during the base _ready for characters with no weapon slots.
	if not steam_connection:
		_has_player_selected[p_player_index] = true
		return
	
	._set_selected_element(p_player_index)
	
	if steam_connection.get_lobby_index_for_player(steam_connection.steam_id) == p_player_index:
		steam_connection.weapon_selected()


func _on_selections_completed() -> void:
	if is_multiplayer_lobby:
		if not steam_connection.is_host():
			return
	else:
		._on_selections_completed()
		return
	
	
	for player_index in RunData.get_player_count():
		var chosen_item = _get_panels()[player_index]
		var weapon = _player_weapons[player_index]
		
		if chosen_item.item_data == null or weapon == null:
			var available_elements: = []
			for element in displayed_elements[player_index]:
				if not element.is_locked:
					available_elements.push_back(element)
			weapon = Utils.get_rand_element(available_elements)
			_player_weapons[player_index] = weapon
		
		if weapon:
			var _weapon = RunData.add_weapon(weapon, player_index, true)
	
	RunData.add_starting_items_and_weapons()
	
	var all_selected_weapons = []
	for player_index in RunData.get_player_count():
		var selected_weapons = []
		for owned_weapon in RunData.players_data[player_index].weapons:
			selected_weapons.push_back(weapon_item_to_string(owned_weapon))
		all_selected_weapons.push_back(selected_weapons)
	
	steam_connection.send_weapon_selection_completed(all_selected_weapons)
	
	_change_scene(MenuData.difficulty_selection_scene)


func _weapon_selection_completed(selected_weapons : Array) -> void:
	for player_index in RunData.get_player_count():
		RunData.players_data[player_index].weapons.clear()
		for weapon_index in selected_weapons[player_index].size():
			RunData.players_data[player_index].weapons.push_back(selections_by_string_key[selected_weapons[player_index][weapon_index]])
	
	_change_scene(MenuData.difficulty_selection_scene)
