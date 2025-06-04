extends "res://ui/menus/ingame/pause_menu.gd"

var steam_connection
var brotatogether_options

var is_multiplayer_lobby = false


# Called when the node enters the scene tree for the first time.
func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"


func on_game_lost_focus()->void :
	if steam_connection.game_lobby_id > 0:
		return
	.on_game_lost_focus()
