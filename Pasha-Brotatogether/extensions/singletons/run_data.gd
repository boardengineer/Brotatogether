extends "res://singletons/run_data.gd"

var steam_connection
var brotatogether_options

var is_multiplayer_lobby = false


func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"
	is_multiplayer_lobby = brotatogether_options.joining_multiplayer_lobby


func lock_player_shop_item(item_data: ItemParentData, wave_value: int, player_index: int)->void :
	if is_multiplayer_lobby:
		if steam_connection.is_host():
			.lock_player_shop_item(item_data, wave_value, player_index)
		steam_connection.shop_lock_item(item_data.name, wave_value)
	else:
		.lock_player_shop_item(item_data, wave_value, player_index)


func unlock_player_shop_item(item_data: ItemParentData, player_index: int)->void :
	if is_multiplayer_lobby:
		if steam_connection.is_host():
			.unlock_player_shop_item(item_data, player_index)
		steam_connection.shop_unlock_item(item_data.name
		)
	else:
		.unlock_player_shop_item(item_data, player_index)
