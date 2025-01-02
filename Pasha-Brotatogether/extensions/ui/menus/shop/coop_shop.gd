extends "res://ui/menus/shop/coop_shop.gd"


var steam_connection
var brotatogether_options

var is_multiplayer_lobby = false

# If true, the steam logic will be skipped to avoid duplicate rpc chains.
var is_self_call = false

func _ready():
	steam_connection = $"/root/SteamConnection"
	
	steam_connection.connect("client_shop_focus_updated", self, "_client_shop_focus_updated")
	steam_connection.connect("client_shop_go_button_pressed", self, "_client_shop_go_button_pressed")
	steam_connection.connect("client_shop_discard_weapon", self, "_client_shop_discard_weapon")
	steam_connection.connect("client_shop_combine_weapon", self, "_client_shop_combine_weapon")
	steam_connection.connect("client_shop_buy_item", self, "_client_shop_buy_item")
	steam_connection.connect("client_shop_lock_item", self, "_client_shop_lock_item")
	
	steam_connection.connect("shop_lobby_update", self, "_shop_lobby_update")
	
	brotatogether_options = $"/root/BrotogetherOptions"
	is_multiplayer_lobby = brotatogether_options.joining_multiplayer_lobby


func _client_shop_focus_updated(shop_item_string : String, player_index : int) -> void:
	is_self_call = true
	_on_shop_item_focused(_shop_item_for_string(shop_item_string, player_index), player_index)


func _on_shop_item_focused(shop_item: ShopItem, player_index : int) -> void:
	._on_shop_item_focused(shop_item, player_index)
	
	if is_multiplayer_lobby:
		if is_self_call:
			is_self_call = false
		else:
			steam_connection.shop_item_focused(_string_for_shop_item(shop_item))


func _on_item_discard_button_pressed(weapon_data: WeaponData, player_index: int)->void :
	if is_multiplayer_lobby:
		if steam_connection.is_host():
			._on_item_discard_button_pressed(weapon_data, player_index)
		steam_connection.shop_weapon_discard(_string_for_weapon(weapon_data))
	else:
		._on_item_discard_button_pressed(weapon_data, player_index)


func _client_shop_discard_weapon(weapon_string : String, player_index : int) -> void:
	_on_item_discard_button_pressed(_weapon_for_string(weapon_string, player_index), player_index)


func _on_GoButton_pressed(player_index: int) -> void:
	if is_multiplayer_lobby:
		if steam_connection.is_host():
			._on_GoButton_pressed(player_index)
		steam_connection.shop_go_button_pressed(_player_pressed_go_button[player_index])
	else:
		._on_GoButton_pressed(player_index)


func _client_shop_go_button_pressed(player_index : int, latest_go_state : bool) -> void:
	# Make the go function change the state to the new state by setting to the
	# opposite
	_player_pressed_go_button[player_index] = not latest_go_state
	_on_GoButton_pressed(player_index)


func on_shop_item_bought(shop_item: ShopItem, player_index: int) -> void:
	if is_multiplayer_lobby:
		if steam_connection.is_host():
			.on_shop_item_bought(shop_item, player_index)
		steam_connection.shop_buy_item(_string_for_shop_item(shop_item))
	else:
		.on_shop_item_bought(shop_item, player_index)


func _client_shop_buy_item(item_string : String, player_index : int) -> void:
	on_shop_item_bought(_shop_item_for_string(item_string, player_index), player_index)


func _on_item_combine_button_pressed(weapon_data: WeaponData, player_index: int, is_upgrade: bool = false)->void :
	if is_multiplayer_lobby:
		if steam_connection.is_host():
			._on_item_combine_button_pressed(weapon_data, player_index, is_upgrade)
		steam_connection.shop_combine_weapon(_string_for_weapon(weapon_data), is_upgrade)
	else:
		._on_item_combine_button_pressed(weapon_data, player_index, is_upgrade)


func _client_shop_combine_weapon(weapon_string : String, is_upgrade: bool, player_index : int) -> void:
	_on_item_combine_button_pressed(_weapon_for_string(weapon_string, player_index), player_index, is_upgrade)


func _client_shop_lock_item(item_string : String, wave_value: int, player_index: int) -> void:
	RunData.lock_player_shop_item(_shop_item_for_string(item_string, player_index).item_data, wave_value, player_index)


func _client_shop_unlock_item(item_string : String, player_index : int) -> void:
	RunData.unlock_player_shop_item(_shop_item_for_string(item_string, player_index).item_data, player_index)


func send_shop_state() -> void:
	var result_dict : Dictionary = {}
	
	var players_array = []
	var player_count: int = RunData.get_player_count()
	for player_index in player_count:
		var player_dict = {}
		var free_rerolls = RunData.get_player_effect("free_rerolls", player_index)
		var shop_items = []
		for item in _shop_items[player_index]:
			var item_dict : Dictionary = {}
			
			item_dict["ID"] = item[0].my_id
			item_dict["WAVE_VALUE"] = item[1]
			
			shop_items.push_back(item_dict)
		player_dict["SHOP_ITEMS"] = shop_items
		
		var locked_items = []
		for item in RunData.locked_shop_items[player_index]:
			var item_dict : Dictionary = {}
			item_dict["ID"] = item[0].my_id
			item_dict["WAVE_VALUE"] = item[1]
		player_dict["LOCKED_ITEMS"] = locked_items
		
		var weapons_array = []
		for weapon in RunData.get_player_weapons(player_index):
			weapons_array.push_back(_dictionary_for_weapon(weapon))
		player_dict["WEAPONS"] = weapons_array
		
		var items_array = []
		for item in RunData.get_player_items(player_index):
			items_array.push_back(_dictionary_for_inventory_item(item))
		player_dict["ITEMS"] = items_array
		
		player_dict["GOLD"] = RunData.get_player_gold(player_index)
		
		players_array.push_back(player_dict)
	
	result_dict["PLAYERS"] = players_array
	steam_connection.send_shop_update(result_dict)


func _update_shop(shop_dictionary : Dictionary) -> void:
	if not shop_dictionary.has("PLAYERS"):
		print("WARNING - received shop update without PLAYERS element, ignoring; data:", shop_dictionary)
		return
	
	if steam_connection.is_host():
		print("WARNING - host shouldn't be updating for remote, returning; data:", shop_dictionary)
		return
	
	for player_index in shop_dictionary["PLAYERS"].size():
		_shop_items[player_index].clear()
		
		var player_dict = shop_dictionary["PLAYERS"][player_index]
		
		for shop_item_dict in player_dict["SHOP_ITEMS"]:
			_shop_items.push_back(_shop_item_for_dictionary(shop_item_dict))
		
		var player_gear_container = _get_gear_container(player_index)
		
		RunData.players_data[player_index].weapons.clear()
		for weapon in player_dict["WEAPONS"]:
			RunData.players_data[player_index].weapons.push_back(_weapon_for_dictionary(weapon))
		player_gear_container.set_weapons_data(RunData.players_data[player_index].weapons)
		
		RunData.players_data[player_index].items.clear()
		for item in player_dict["ITEMS"]:
			RunData.players_data[player_index].items.push_back(_inventory_item_for_dictionary(item))
		player_gear_container.set_items_data(RunData.players_data[player_index].items)
		
		RunData.players_data[player_index].gold = player_dict["GOLD"]
		_get_gold_label(player_index).update_value(RunData.players_data[player_index].gold)


func _dictionary_for_inventory_item(item : ItemData) -> Dictionary:
	return {
		"ID" : item.my_id
	}


func _inventory_item_for_dictionary(item_dict : Dictionary) -> ItemData:
	var query_id = item_dict["ID"]
	
	for item in ItemService.items:
		if item.my_id == query_id:
			return item.duplicate()
	
	return null


func _dictionary_for_shop_item(shop_item : Array) -> Dictionary:
	return {
		"ID" : shop_item[0].my_id,
		"WAVE_VALUE": shop_item[1],
	}


func _shop_item_for_dictionary(shop_item_dict : Dictionary) -> Array:
	var item_element
	
	var query_id = shop_item_dict["ID"]
	for item in ItemService.items:
		if item.my_id == query_id:
			item_element = item.duplicate()
	for weapon in ItemService.weapons:
		if weapon.my_id == query_id:
			item_element = weapon.duplicate()
	
	return [item_element, shop_item_dict["WAVE_VALUE"]]


func _dictionary_for_weapon(weapon_data : WeaponData) -> Dictionary:
	return {
		"ID" : weapon_data.my_id
	}


func _weapon_for_dictionary(weapon_dict : Dictionary) -> WeaponData:
	var query_id = weapon_dict["ID"]
	
	for weapon in ItemService.weapons:
		if weapon.my_id == query_id:
			return weapon.duplicate()
	
	return null


func _string_for_weapon(weapon_data : WeaponData) -> String:
	return weapon_data.name


func _weapon_for_string(weapon_string : String, player_index : int) -> WeaponData:
	for element in _get_gear_container(player_index).weapons_container._elements.get_children():
		if _string_for_weapon(element.item) == weapon_string:
			return element.item
	return null


func _string_for_shop_item(shop_item : ShopItem) -> String:
	return shop_item.item_data.name


func _shop_item_for_string(shop_item_string : String, player_index : int) -> ShopItem:
	var player_shop_items = _shop_items[player_index]
	for item in player_shop_items:
		if _string_for_shop_item(item) == shop_item_string:
			return item
	
	return null



