extends Control

onready var player_list = $PlayerList
onready var start_button = $ControlBox/Buttons/StartButton

onready var character_info = $"GameSettings/CharacterBox/CharacterInfo"
onready var weapon_select_info = $"GameSettings/WeaponBox/WeaponInfo"
onready var danger_select_info = $"GameSettings/DangerBox/DangerInfo"

onready var character_select_button = $"GameSettings/CharacterBox/CharacterButton"
onready var weapon_select_button = $"GameSettings/WeaponBox/WeaponButton"
onready var danger_select_button = $"GameSettings/DangerBox/DangerButton"

const player_label_scene = preload("res://mods-unpacked/Pasha-Brotatogether/ui/player_label.tscn")

func _ready():
	var _error = Steam.connect("lobby_chat_update", self, "_on_Lobby_Chat_Update")
	
	if not $"/root/GameController".is_host:
		start_button.disabled = true
		
		character_select_button.hide()
		weapon_select_button.hide()
		danger_select_button.hide()
		
	
	update_player_list()
	update_selections()
	
func update_player_list() -> void:
	# TODO make this work with direct connections too
	var steam_connection = $"/root/SteamConnection"
	steam_connection.update_tracked_players()
	
	for node in player_list.get_children():
		player_list.remove_child(node)
		node.queue_free()
		
	var game_controller = $"/root/GameController"
	var host = steam_connection.get_lobby_host()
	
	for player_id in game_controller.tracked_players:
		var username = game_controller.tracked_players[player_id].username
		var label = player_label_scene.instance()
		if username == host:
			label.text = username + " (HOST)"
			label.set("custom_colors/font_color","#FF0000")
		else:
			label.text = username
		label.show()
		player_list.add_child(label)

func _on_Lobby_Chat_Update(_lobby_id: int, _change_id: int, _making_change_id: int, _chat_state: int) -> void:
	update_player_list()

func update_selections() -> void:
	if RunData.current_character:
		weapon_select_button.disabled = false
		danger_select_button.disabled = false
		character_info.set_data(RunData.current_character)
		
		if RunData.starting_weapon:
			danger_select_button.disabled = false
			weapon_select_info.set_data(RunData.starting_weapon)
			
			var difficulty = ProgressData.get_character_difficulty_info(RunData.current_character.my_id, RunData.current_zone)
			danger_select_info.set_data(ItemService.difficulties[difficulty.difficulty_selected_value])
		
		
	else:
		# reset weapon selection
		weapon_select_button.disabled = true
		danger_select_button.disabled = true
	var game_controller = $"/root/GameController"
	
	if game_controller.is_host:
		game_controller.send_lobby_update(get_lobby_info_dictionary())
	

func _on_StartButton_pressed():
	var game_controller = $"/root/GameController"
	if not game_controller.is_host:
		return
		
	game_controller.is_source_of_truth = false
	var game_mode = "async"
	
	var game_info = {"current_wave":1, "mode":game_mode}
	
	game_info ["lobby_info"] = get_lobby_info_dictionary()
	
	game_controller.send_start_game(game_info)
	game_controller.game_mode = game_mode

	game_controller.start_game(game_info)
	
	var steam_connection = $"/root/SteamConnection"
	steam_connection.close_lobby()


func _on_CharacterButton_pressed():
	$"/root/GameController".back_to_lobby = true
	
	RunData.weapons = []
	RunData.items = []
	RunData.effects = RunData.init_effects()
	RunData.current_character = null
	RunData.starting_weapon = null
	
	var _error = get_tree().change_scene(MenuData.character_selection_scene)

func _on_WeaponButton_pressed():
	RunData.weapons = []
	RunData.items = []
	RunData.add_character(RunData.current_character)
	RunData.effects = RunData.init_effects()
	RunData.starting_weapon = null
	
	$"/root/GameController".back_to_lobby = true
	var _error = get_tree().change_scene(MenuData.weapon_selection_scene)

func _on_DangerButton_pressed():
	$"/root/GameController".back_to_lobby = true
	var _error = get_tree().change_scene(MenuData.difficulty_selection_scene)

func get_lobby_info_dictionary() -> Dictionary:
	var result = {}
	
	if RunData.current_character:
		result["character"] = ItemService.get_element(ItemService.characters, RunData.current_character.my_id).get_path()
		var difficulty = ProgressData.get_character_difficulty_info(RunData.current_character.my_id, RunData.current_zone)
		danger_select_info.set_data(ItemService.difficulties[difficulty.difficulty_selected_value])
		result["danger"] = difficulty.difficulty_selected_value
		
	if RunData.starting_weapon:
		result["weapon"] = ItemService.get_element(ItemService.weapons, RunData.starting_weapon.my_id).get_path()
		
	return result
	
func clear_selections() -> void:
	RunData.weapons = []
	RunData.items = []
	RunData.effects = RunData.init_effects()
	RunData.current_character = null
	RunData.init_appearances_displayed()
	
func remote_update_lobby(lobby_info:Dictionary) -> void:
	# Remote only
	if $"/root/GameController".is_host:
		return
	
	RunData.weapons = []
	RunData.items = []
	RunData.effects = RunData.init_effects()
	RunData.current_character = null
	RunData.starting_weapon = null
	
	if lobby_info.has("character"):
		RunData.add_character(load(lobby_info.character))
		
	if lobby_info.has("weapon"):
		var _unused_weapon = RunData.add_weapon(load(lobby_info.weapon), true)
		
	if lobby_info.has("danger"):
		var character_difficulty = ProgressData.get_character_difficulty_info(RunData.current_character.my_id, RunData.current_zone)
		character_difficulty.difficulty_selected_value = lobby_info.danger
	
	update_selections()

func _input(event:InputEvent)->void :
	manage_back(event)

func manage_back(event:InputEvent)->void :
	if event.is_action_pressed("ui_cancel"):
		var game_controller = $"/root/GameController"
	
		if game_controller.is_host:
			var steam_connection = $"/root/SteamConnection"
			steam_connection.close_lobby()
		
		RunData.current_zone = 0
		RunData.reload_music = false
		var _error = get_tree().change_scene(MenuData.title_screen_scene)

func _on_StartButton2_pressed():
	var game_controller = $"/root/GameController"
	if not game_controller.is_host:
		return
		
	game_controller.is_source_of_truth = true
	var game_mode = "shared"
	
	var game_info = {"current_wave":1, "mode":game_mode}
	
	game_info["lobby_info"] = get_lobby_info_dictionary()
	
	game_controller.send_start_game(game_info)
	game_controller.game_mode = game_mode

	game_controller.start_game(game_info)
	
	var steam_connection = $"/root/SteamConnection"
	steam_connection.close_lobby()
