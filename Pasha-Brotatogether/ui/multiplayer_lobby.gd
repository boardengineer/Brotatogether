extends VBoxContainer

onready var player_list = $HBoxContainer/PlayerList

func _ready():
	var steam_connection = $"/root/SteamConnection"
	steam_connection.connect("lobby_chat_update", self, "_on_Lobby_Chat_Update")
	
	update_player_list()
	
func update_player_list() -> void:
	# TODO make this work with direction connections too
	var steam_connection = $"/root/SteamConnection"
	steam_connection.update_tracked_players()
	
	var game_controller = $"/root/GameController"
	for player_id in game_controller.tracked_players:
		var label = Label.new()
		label.text = game_controller.tracked_players[player_id].username
		player_list.add_child(label)

func _on_Lobby_Chat_Update(lobby_id: int, change_id: int, making_change_id: int, chat_state: int) -> void:
	print_debug("someone joined inside the lobby")
	update_player_list()
