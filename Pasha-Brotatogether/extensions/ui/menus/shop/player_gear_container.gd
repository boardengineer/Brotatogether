extends "res://ui/menus/shop/player_gear_container.gd"

var steam_connection
var brotatogether_options

var in_multiplayer_game = false


func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"
	in_multiplayer_game = brotatogether_options.in_multiplayer_game


func set_items_data(items: Array)->void :
	if in_multiplayer_game:
		items_container.set_data("ITEMS", Category.ITEM, items, false, true)
	else:
		.set_items_data(items)
