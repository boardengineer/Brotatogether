extends "res://ui/menus/shop/shop_item.gd"

var steam_connection
var brotatogether_options

var in_multiplayer_game = false


func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"
	in_multiplayer_game = brotatogether_options.in_multiplayer_game


func deactivate()->void :
	if in_multiplayer_game:
		if steam_connection.is_host():
			.deactivate()
			return
		else:
			modulate = Color(1, 1, 1, 0)
			_button.disable()
			_lock_icon.hide()
			locked = false
			active = false
			emit_signal("shop_item_deactivated", self)
	else:
		.deactivate()
