extends HBoxContainer

var lobby_id
var lobby_name

var steam_connection

onready var lobby_name_label = $"%LobbyName"


func _ready():
	steam_connection = $"/root/SteamConnection"
	lobby_name_label.text = lobby_name


func _on_join_button_pressed():
	# Version/DLC/mod compatibility is checked before we actually join (see SteamConnection).
	steam_connection.attempt_join_game_lobby(lobby_id)
