extends "res://ui/menus/shop/coop_shop.gd"


var coop_steam_connection
var coop_brotatogether_options

var coop_is_multiplayer_lobby = false

# If true, the steam logic will be skipped to avoid duplicate rpc chains.
var coop_is_self_call = false

func _ready():
	coop_steam_connection = $"/root/SteamConnection"
	
	coop_steam_connection.connect("client_shop_focus_updated", self, "_client_shop_focus_updated")
	
	coop_brotatogether_options = $"/root/BrotogetherOptions"
	coop_is_multiplayer_lobby = coop_brotatogether_options.joining_multiplayer_lobby


func _client_shop_focus_updated(shop_item_string : String, player_index : int) -> void:
	coop_is_self_call = true
	_on_shop_item_focused(_shop_item_for_string(shop_item_string, player_index), player_index)


func _on_shop_item_focused(shop_item: ShopItem, player_index : int) -> void:
	._on_shop_item_focused(shop_item, player_index)
	
	if coop_is_multiplayer_lobby:
		if coop_is_self_call:
			coop_is_self_call = false
		else:
			coop_steam_connection.shop_item_focused(_string_for_shop_item(shop_item))


func _string_for_shop_item(shop_item : ShopItem) -> String:
	return shop_item.item_data.name


func _shop_item_for_string(shop_item_string : String, player_index : int) -> ShopItem:
	var player_shop_items = _shop_items[player_index]
	for item in player_shop_items:
		if _string_for_shop_item(item) == shop_item_string:
			return item
	
	return null
