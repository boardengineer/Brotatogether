extends VBoxContainer

onready var player_list = $HBoxContainer/PlayerList
onready var start_button = $HBoxContainer/ControlBox/Buttons/StartButton

onready var character_info = $"HBoxContainer/GameSettings/CharacterBox/CharacterInfo"
onready var weapon_select_info = $"HBoxContainer/GameSettings/WeaponBox/WeaponInfo"
onready var danger_select_info = $"HBoxContainer/GameSettings/DangerBox/DangerInfo"

onready var weapon_select_button = $"HBoxContainer/GameSettings/WeaponBox/ButtonContainer/WeaponButton"
onready var danger_select_button = $"HBoxContainer/GameSettings/DangerBox/ButtonContainer/DangerButton"

func _ready():
	var steam_connection = $"/root/SteamConnection"
	Steam.connect("lobby_chat_update", self, "_on_Lobby_Chat_Update")
	
	if not $"/root/GameController".is_host:
		start_button.disabled = true
	
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
	for player_id in game_controller.tracked_players:
		var label = Label.new()
		label.text = game_controller.tracked_players[player_id].username
		player_list.add_child(label)

func _on_Lobby_Chat_Update(lobby_id: int, change_id: int, making_change_id: int, chat_state: int) -> void:
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

	get_tree().change_scene(MenuData.game_scene)


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
		RunData.add_weapon(load(lobby_info.weapon), true)
		
	if lobby_info.has("danger"):
		var character_difficulty = ProgressData.get_character_difficulty_info(RunData.current_character.my_id, RunData.current_zone)
		character_difficulty.difficulty_selected_value = lobby_info.danger
		
	print("sent ", lobby_info)
	
	update_selections()
