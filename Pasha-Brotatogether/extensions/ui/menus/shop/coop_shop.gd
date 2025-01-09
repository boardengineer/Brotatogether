extends "res://ui/menus/shop/coop_shop.gd"


var steam_connection
var brotatogether_options

var in_multiplayer_game = false

# If true, the steam logic will be skipped to avoid duplicate rpc chains.
var is_self_call = false

var player_in_scene = [true, false, false, false]
var waiting_to_start_shop = false

func _ready():
	steam_connection = $"/root/SteamConnection"
	
	brotatogether_options = $"/root/BrotogetherOptions"
	in_multiplayer_game = brotatogether_options.in_multiplayer_game
	
	if in_multiplayer_game:
		waiting_to_start_shop = true
		
		steam_connection.connect("client_status_received", self, "_client_status_received")
		steam_connection.connect("shop_lobby_update", self, "_update_shop")
		steam_connection.connect("client_shop_focus_updated", self, "_client_shop_focus_updated")
		steam_connection.connect("client_shop_go_button_pressed", self, "_client_shop_go_button_pressed")
		steam_connection.connect("client_shop_discard_weapon", self, "_client_shop_discard_weapon")
		steam_connection.connect("client_shop_combine_weapon", self, "_client_shop_combine_weapon")
		steam_connection.connect("client_shop_buy_item", self, "_client_shop_buy_item")
		steam_connection.connect("client_shop_lock_item", self, "_client_shop_lock_item")
		steam_connection.connect("client_shop_focus_inventory_element", self, "_client_focused_inventory_element")


func _process(delta):
	if in_multiplayer_game:
		if waiting_to_start_shop:
			if steam_connection.is_host():
				var all_players_entered = true
				for player_index in RunData.get_player_count():
					if not player_in_scene[player_index]:
						all_players_entered = false
						break
				if all_players_entered:
					waiting_to_start_shop = false
					send_shop_state()


func _client_status_received(client_data : Dictionary, player_index : int) -> void:
	if waiting_to_start_shop:
		if client_data["CURRENT_SCENE"] == get_tree().current_scene.name:
			player_in_scene[player_index] = true


func _on_element_focused(element: InventoryElement, player_index: int)->void :
	._on_element_focused(element,player_index)
	
	if in_multiplayer_game:
		steam_connection.shop_focus_inventory_element(_dictionary_for_focus_inventory_element(element, player_index))


func _client_shop_focus_updated(shop_item_string : String, player_index : int) -> void:
	print_debug("received client focus from ", player_index, " ", shop_item_string)
	is_self_call = true
	
	var shop_item : ShopItem = _shop_item_for_string(shop_item_string, player_index)
	Utils.get_focus_emulator(player_index).focused_control = shop_item._button
	_on_shop_item_focused(shop_item, player_index)


func _on_shop_item_focused(shop_item: ShopItem, player_index : int) -> void:
	print_debug("shop item focused")
	
	._on_shop_item_focused(shop_item, player_index)
	
	if in_multiplayer_game:
		if is_self_call:
			is_self_call = false
		else:
			steam_connection.shop_item_focused(_string_for_shop_item(shop_item))


func _on_item_discard_button_pressed(weapon_data: WeaponData, player_index: int)->void :
	if in_multiplayer_game:
		if steam_connection.is_host():
			._on_item_discard_button_pressed(weapon_data, player_index)
		steam_connection.shop_weapon_discard(_string_for_weapon(weapon_data))
	else:
		._on_item_discard_button_pressed(weapon_data, player_index)


func _client_shop_discard_weapon(weapon_string : String, player_index : int) -> void:
	_on_item_discard_button_pressed(_weapon_for_string(weapon_string, player_index), player_index)


func _on_GoButton_pressed(player_index: int) -> void:
	if in_multiplayer_game:
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
	if in_multiplayer_game:
		if steam_connection.is_host():
			.on_shop_item_bought(shop_item, player_index)
		steam_connection.shop_buy_item(_string_for_shop_item(shop_item))
	else:
		.on_shop_item_bought(shop_item, player_index)


func _client_shop_buy_item(item_string : String, player_index : int) -> void:
	on_shop_item_bought(_shop_item_for_string(item_string, player_index), player_index)


func _on_item_combine_button_pressed(weapon_data: WeaponData, player_index: int, is_upgrade: bool = false)->void :
	if in_multiplayer_game:
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
		player_dict["FOCUS"] = _focus_dictionary_for_player(player_index)
		
		players_array.push_back(player_dict)
	
	result_dict["PLAYERS"] = players_array
	
	print_debug("sending shop state with dict ", result_dict)
	steam_connection.send_shop_update(result_dict)


func _update_shop(shop_dictionary : Dictionary) -> void:
	if not shop_dictionary.has("PLAYERS"):
		print("WARNING - received shop update without PLAYERS element, ignoring; data:", shop_dictionary)
		return
	
	if steam_connection.is_host():
		print("WARNING - host shouldn't be updating for remote, returning; data:", shop_dictionary)
		return
	
	print_debug("updating shop for dictionary - ", shop_dictionary)
	
	for player_index in shop_dictionary["PLAYERS"].size():
		_shop_items[player_index].clear()
		
		var player_dict = shop_dictionary["PLAYERS"][player_index]
		
		for shop_item_dict in player_dict["SHOP_ITEMS"]:
			var shop_item = _shop_item_for_dictionary(shop_item_dict)
			_shop_items[player_index].push_back(_shop_item_for_dictionary(shop_item_dict))
		_get_shop_items_container(player_index).set_shop_items(_shop_items[player_index])
		
		var player_gear_container = _get_gear_container(player_index)
		
		RunData.players_data[player_index].weapons.clear()
		for weapon in player_dict["WEAPONS"]:
			RunData.players_data[player_index].weapons.push_back(_weapon_for_dictionary(weapon))
		player_gear_container.set_weapons_data(RunData.players_data[player_index].weapons)
		
		RunData.players_data[player_index].items.clear()
		for item in player_dict["ITEMS"]:
			RunData.players_data[player_index].items.push_back(_inventory_item_for_dictionary(item))
		player_gear_container.set_items_data(RunData.players_data[player_index].items)
		
		if player_dict.has("FOCUS"):
			_set_client_focus_for_player(player_dict["FOCUS"], player_index)
		else:
			print_debug("WARN - missing focus for player ", player_index, " ", player_dict)
		
		RunData.players_data[player_index].gold = player_dict["GOLD"]
		_get_gold_label(player_index).update_value(RunData.players_data[player_index].gold)


func _dictionary_for_inventory_item(item : ItemData) -> Dictionary:
	return {
		"ID" : item.my_id
	}


func _client_focused_inventory_element(data : Dictionary, player_index : int) -> void:
	var focused_element = _focus_inventory_item_for_dictionary(data, player_index)
	
	Utils.get_focus_emulator(player_index).focused_control = focused_element
	_on_element_focused(focused_element, player_index)


func _dictionary_for_focus_inventory_element(element: InventoryElement, player_index : int) -> Dictionary:
	var gear_container : PlayerGearContainer = _get_gear_container(player_index)
	
	var weapons : Array = gear_container.weapons_container._elements.get_children()
	for weapon_index in weapons.size():
		if element == weapons[weapon_index]:
			return {
				"TYPE" : "WEAPON",
				"INDEX" : weapon_index
			}
	
	var items : Array = gear_container.items_container._elements.get_children()
	for item_index in items.size():
		if element == items[item_index]:
			return {
				"TYPE" : "ITEM",
				"INDEX" : item_index
			}
	
	return {}


func _focus_inventory_item_for_dictionary(item_dict : Dictionary, player_index : int) -> InventoryElement:
	var gear_container : PlayerGearContainer = _get_gear_container(player_index)
	
	if item_dict["TYPE"] == "WEAPON":
		return gear_container.weapons_container._elements.get_children()[item_dict["INDEX"]]
	elif item_dict["TYPE"] == "ITEM":
		return gear_container.items_container._elements.get_children()[item_dict["INDEX"]]
	else:
		print("ERR - Focusing inventgory element of unknown type ", item_dict)
	
	return null


func _inventory_item_for_dictionary(item_dict : Dictionary) -> ItemData:
	var query_id = item_dict["ID"]
	
	print_debug("looking for item with id ", query_id)
	for item in ItemService.items:
		if item.my_id == query_id:
			return item.duplicate()
	
	for character in ItemService.characters:
		if character.my_id == query_id:
			return character.duplicate()
	
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
	for item in _get_shop_items_container(player_index).get_children():
		if item.item_data.name == shop_item_string:
			return item
	
	return null


func fill_shop_items(player_locked_items: Array, player_index: int, just_entered_shop: bool = false) -> void:
	print_debug("an override? ", $"/root/BrotogetherOptions".in_multiplayer_game, " ", $"/root/SteamConnection".is_host())
	if $"/root/BrotogetherOptions".in_multiplayer_game:
		if $"/root/SteamConnection".is_host():
			.fill_shop_items(player_locked_items, player_index, just_entered_shop)
	else:
		.fill_shop_items(player_locked_items, player_index, just_entered_shop)


func _focus_dictionary_for_player(player_index : int) -> Dictionary:
	var focused_control : Control = Utils.get_focus_emulator(player_index).focused_control
	for shop_item in _get_shop_items_container(player_index).get_children():
		if shop_item._button == focused_control:
			return {
				"TYPE" : "SHOP_ITEM",
				"ID" : _string_for_shop_item(shop_item)
			}
	
	var gear_container : PlayerGearContainer = _get_gear_container(player_index)
	var weapons : Array = gear_container.weapons_container._elements.get_children()
	for weapon_index in weapons.size():
		if focused_control == weapons[weapon_index]:
			return {
				"TYPE" : "WEAPON",
				"INDEX" : weapon_index
			}
	
	var items : Array = gear_container.items_container._elements.get_children()
	for item_index in items.size():
		if focused_control == items[item_index]:
			return {
				"TYPE" : "ITEM",
				"INDEX" : item_index
			}
	
	return {}


func _set_client_focus_for_player(focus_dict : Dictionary, player_index : int) -> void:
	if not focus_dict.has("TYPE"):
		print_debug("ERR - unkown client focus ", player_index, " ", focus_dict)
	
	var focus_type : String = focus_dict["TYPE"]
	
	if focus_type == "ITEM" or focus_type == "WEAPON":
		_client_focused_inventory_element(focus_dict, player_index)
	elif focus_type == "SHOP_ITEM":
		_client_shop_focus_updated(focus_dict["ID"], player_index)
	else:
		print_debug("ERR - Invalid focus dict", focus_dict, " ", player_index)
