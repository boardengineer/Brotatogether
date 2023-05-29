extends VBoxContainer

onready var player_list = $HBoxContainer/PlayerList

func _ready():
	var steam_connection = $"/root/SteamConnection"
	Steam.connect("lobby_chat_update", self, "_on_Lobby_Chat_Update")
	
	update_player_list()
	
func update_player_list() -> void:
	# TODO make this work with direction connections too
	var steam_connection = $"/root/SteamConnection"
	steam_connection.update_tracked_players()
	
	for node in player_list.get_children():
		player_list.remove_child(node)
		node.queue_free()
		
	var game_controller = $"/root/GameController"
	for player_id in game_controller.tracked_players:
		var label = Label.new()
		label.text = game_controller.tracked_players[player_id].username
		player_list.add_child(label)

func _on_Lobby_Chat_Update(lobby_id: int, change_id: int, making_change_id: int, chat_state: int) -> void:
	update_player_list()

func _on_StartButton_pressed():
	var game_controller = $"/root/GameController"
	if game_controller.is_host:
		game_controller.is_source_of_truth = false
		
	var game_mode = "async"
		
	game_controller.send_start_game({"current_wave":1, "mode":game_mode})
	game_controller.game_mode = game_mode
	RunData.add_character(preload("res://items/characters/well_rounded/well_rounded_data.tres"))
	RunData.add_weapon(preload("res://weapons/ranged/minigun/4/minigun_4_data.tres"), true)
#	RunData.add_weapon(preload("res://weapons/ranged/pistol/1/pistol_data.tres"), true)
	get_tree().change_scene(MenuData.game_scene)
