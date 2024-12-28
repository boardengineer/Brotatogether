extends "res://ui/menus/shop/base_shop.gd"

var steam_connection
var brotatogether_options

var is_multiplayer_lobby = false

# If true, the steam logic will be skipped to avoid duplicate rpc chains.
var is_self_call = false


func _ready():
	steam_connection = $"/root/SteamConnection"
	
	steam_connection.connect("client_shop_go_button_pressed", self, "_client_shop_go_button_pressed")
	steam_connection.connect("client_shop_discard_pressed", self, "_client_shop_discard_pressed")
	steam_connection.connect("client_shop_buy_item", self, "_client_shop_buy_item")
	steam_connection.connect("client_shop_locked_item", self, "_client_shop_locked_item")
	steam_connection.connect("client_shop_buy_weapon", self, "_client_shop_buy_weapon")
	steam_connection.connect("client_shop_combine_weapon", self, "_client_shop_combine_weapon")
	steam_connection.connect("shop_lobby_update", self, "_shop_lobby_update")
	
	brotatogether_options = $"/root/BrotogetherOptions"
	is_multiplayer_lobby = brotatogether_options.joining_multiplayer_lobby


func _on_GoButton_pressed(player_index: int) -> void:
	._on_GoButton_pressed(player_index)
	
	if is_self_call:
		is_self_call = false
	else:
		pass


func _client_shop_go_button_pressed(player_index : int, latest_go_state : bool) -> void:
	# Make the go function change the state to the new state by setting to the
	# opposite
	_player_pressed_go_button[player_index] = not latest_go_state
	is_self_call = true
	_on_GoButton_pressed(player_index)


func _client_shop_go_button_exited(player_index : int) -> void:
	pass


func _client_shop_discard_pressed(weapon_string : String, player_index: int) -> void:
	pass


func _client_shop_buy_item(item_string : String, player_index : int) -> void:
	pass


func _client_shop_locked_item(item_string : String, player_index : int) -> void:
	pass


func _client_shop_buy_weapon(weapon_string : String, player_index : int) -> void:
	pass


func _client_shop_combine_weapon(weapon_string : String, player_index : int) -> void:
	pass


func _shop_lobby_update() -> void:
	pass


func _shop_item_to_string(shop_item_string : String) -> ShopItem:
	return null
