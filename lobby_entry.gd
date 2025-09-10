extends HBoxContainer

var lobby_id
var lobby_name

var steam_connection

onready var lobby_name_label = $"%LobbyName"

func _ready():
	steam_connection = $"/root/SteamConnection"
	lobby_name_label.text = lobby_name

func _on_join_button_pressed():
	var result = Steam.joinLobby(lobby_id)
	if result != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		var new_message_node = preload("res://mods-unpacked/Pasha-Brotatogether/ui/chat/chat_message.tscn").instance()
		new_message_node.message = "Failed to join lobby: " + str(result)
		new_message_node.username = "SYSTEM"
		$"/root/MultiplayerMenu/HBoxContainer/ChatContainer/ScrollContainer/ChatMessages".add_child(new_message_node)
