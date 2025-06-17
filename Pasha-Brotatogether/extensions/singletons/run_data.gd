extends "res://singletons/run_data.gd"

var steam_connection
var brotatogether_options

var is_multiplayer_lobby = false


func init_multiplayer() -> void:
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"
	
	steam_connection.leave_game_lobby()


func lock_player_shop_item(item_data: ItemParentData, wave_value: int, player_index: int)->void :
	if brotatogether_options.in_multiplayer_game:
		if steam_connection.is_host():
			.lock_player_shop_item(item_data, wave_value, player_index)
		steam_connection.shop_lock_item(item_data.my_id, wave_value)
	else:
		.lock_player_shop_item(item_data, wave_value, player_index)


func unlock_player_shop_item(item_data: ItemParentData, player_index: int)->void :
	if brotatogether_options.in_multiplayer_game:
		if steam_connection.is_host():
			.unlock_player_shop_item(item_data, player_index)
		steam_connection.shop_unlock_item(item_data.my_id)
	else:
		.unlock_player_shop_item(item_data, player_index)
