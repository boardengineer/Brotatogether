extends Control

onready var players_container = get_node("%Players")
onready var start_button = $ControlBox/Buttons/StartButton
onready var outer_options_container = get_node("%OuterOptionsContainer")

onready var game_mode_dropdown:OptionButton = get_node("%GameModeDropdown")
onready var copy_host_toggle:CheckButton = get_node("%CopyHostToggle")
onready var first_death_loss_toggle:CheckButton = get_node("%FirstDeathLossToggle")
onready var shared_gold_toggle:CheckButton = get_node("%ShareGoldToggle")
onready var material_count_slider:SliderOption = get_node("%MaterialCountSlider")
onready var enemy_count_slider:SliderOption = get_node("%EnemyCountSlider")
onready var enemy_hp_slider:SliderOption = get_node("%EnemyHPSlider")
onready var enemy_damage_slider:SliderOption = get_node("%EnemyDamageSlider")
onready var enemy_speed_slider:SliderOption = get_node("%EnemySpeedSlider")

const PlayerSelections = preload("res://mods-unpacked/Pasha-Brotatogether/ui/player_selections.tscn")

onready var selections_by_player = {}
var should_send_lobby_update = false

func _ready():
	var _error = Steam.connect("lobby_chat_update", self, "_on_Lobby_Chat_Update")
	
	var game_controller = $"/root/GameController"
	if not game_controller.is_host:
		start_button.disabled = true
		disable_options()
	
	for child in players_container.get_children():
		players_container.remove_child(child)
	
	game_controller.connect("lobby_info_updated", self, "update_selections")
	init_mode_dropdown()
	update_selections()
	var send_timer = Timer.new()
	send_timer.wait_time = .5
	send_timer.autostart = true
	send_timer.connect("timeout", self, "send_lobby_update")
	add_child(send_timer)


func send_lobby_update() -> void:
	var game_controller = $"/root/GameController"
	if should_send_lobby_update and game_controller.is_host:
		should_send_lobby_update = false
		game_controller.send_lobby_update(game_controller.lobby_data)


func init_mode_dropdown() -> void:
	game_mode_dropdown.clear()
	game_mode_dropdown.add_item("Versus", 0)
	game_mode_dropdown.add_item("Co-op", 1)


func update_player_list() -> void:
	# TODO make this work with direct connections too
	var steam_connection = $"/root/SteamConnection"
	steam_connection.update_tracked_players()


func _on_Lobby_Chat_Update(_lobby_id: int, _change_id: int, _making_change_id: int, _chat_state: int) -> void:
	update_selections()


func update_selections() -> void:
	var game_controller = $"/root/GameController"
	var steam_connection = $"/root/SteamConnection"
	var host = steam_connection.get_lobby_host()
	
	var game_mode = 0
	if game_controller.lobby_data.has("game_mode"):
		game_mode = game_controller.lobby_data["game_mode"]
	
	if game_mode == 1:
		first_death_loss_toggle.show()
		shared_gold_toggle.show()
	else:
		first_death_loss_toggle.hide()
		shared_gold_toggle.hide()
	
	if not game_controller.is_host:
		if game_controller.lobby_data.has("game_mode"):
			game_mode_dropdown.select(game_mode) 
		
		if game_controller.lobby_data.has("copy_host"):
			copy_host_toggle.set_pressed_no_signal(game_controller.lobby_data["copy_host"])
		
		if game_controller.lobby_data.has("material_count"):
			material_count_slider.set_value(game_controller.lobby_data["material_count"])
		
		if game_controller.lobby_data.has("enemy_count"):
			enemy_count_slider.set_value(game_controller.lobby_data["enemy_count"])
		
		if game_controller.lobby_data.has("enemy_hp"):
			enemy_hp_slider.set_value(game_controller.lobby_data["enemy_hp"])
		
		if game_controller.lobby_data.has("enemy_damage"):
			enemy_damage_slider.set_value(game_controller.lobby_data["enemy_damage"])
		
		if game_controller.lobby_data.has("enemy_speed"):
			enemy_speed_slider.set_value(game_controller.lobby_data["enemy_speed"])
	
	var host_dict = {}
	var can_start = true
	for player_id in game_controller.tracked_players:
		if not game_controller.lobby_data["players"].has(player_id):
			game_controller.lobby_data["players"][player_id] = {}
		var username = game_controller.tracked_players[player_id].username
		if username == host:
			host_dict = game_controller.lobby_data["players"][player_id].duplicate()
	
	for player_id in game_controller.tracked_players:
		var username = game_controller.tracked_players[player_id].username
		
		if not selections_by_player.has(player_id):
			if not game_controller.lobby_data["players"].has(player_id):
				game_controller.lobby_data["players"][player_id] = {}
			var player_to_add = PlayerSelections.instance()
			players_container.add_child(player_to_add)
			selections_by_player[player_id] = player_to_add
			
			var name = username
			if username == host:
				name += " (HOST)"
				player_to_add.call_deferred("hide_ready_toggle")
			
			if player_id != game_controller.self_peer_id:
				player_to_add.call_deferred("disable_selections")
				player_to_add.call_deferred("disable_ready_toggle")
			player_to_add.call_deferred("set_player_name", name)
			player_to_add.call_deferred("connect", "ready_toggled", self, "update_ready_toggle")
		
		# co-op mode will only show host 
		var player_selections = selections_by_player[player_id]
		var selections_dict = game_controller.lobby_data["players"][player_id].duplicate()
		if host_dict.has("danger") and game_mode == 1:
			selections_dict["danger"] = host_dict["danger"]
		var can_edit = false
		var lock_danger = false
		
		if username == host:
			if player_id == game_controller.self_peer_id:
				can_edit = true
		else:
			if not selections_dict.has("ready") or not selections_dict["ready"]:
				can_start = false
			if game_controller.lobby_data.has("copy_host") and game_controller.lobby_data["copy_host"]:
				selections_dict = host_dict 
			if game_mode == 1:
				lock_danger = true
			if player_id == game_controller.self_peer_id and not game_controller.lobby_data["copy_host"]:
				can_edit = true
		
		player_selections.call_deferred("set_player_selections", selections_dict, can_edit, lock_danger)
	
	if game_controller.is_host:
		game_controller.send_lobby_update(game_controller.lobby_data)

	if can_start and game_controller.is_host:
		start_button.disabled = false
	else:
		start_button.disabled = true


func _on_StartButton_pressed():
	var game_controller = $"/root/GameController"
	if not game_controller.is_host:
		return
	
	var game_mode = game_mode_dropdown.selected
	game_controller.is_source_of_truth = game_mode == 1
	var game_info = {"current_wave":1, "mode":game_mode, "danger":0}
	
	game_info["lobby_info"] = game_controller.lobby_data
	game_controller.send_start_game(game_info)
	game_controller.game_mode = game_mode

	game_controller.start_game(game_info)
	
	var steam_connection = $"/root/SteamConnection"
	steam_connection.close_lobby()


func _on_CharacterButton_pressed():
	$"/root/GameController".back_to_lobby = true
	
	RunData.weapons = []
	RunData.items = []
	RunData.appearances_displayed = []
	
	RunData.effects = RunData.init_effects()
	RunData.current_character = null
	RunData.starting_weapon = null
	
	var _error = get_tree().change_scene(MenuData.character_selection_scene)


func _on_WeaponButton_pressed():
	RunData.weapons = []
	RunData.items = []
	RunData.appearances_displayed = []
	
	RunData.add_character(RunData.current_character)
	RunData.effects = RunData.init_effects()
	RunData.starting_weapon = null
	
	$"/root/GameController".back_to_lobby = true
	var _error = get_tree().change_scene(MenuData.weapon_selection_scene)


func _on_DangerButton_pressed():
	$"/root/GameController".back_to_lobby = true
	var _error = get_tree().change_scene(MenuData.difficulty_selection_scene)


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
		exit_lobby()


func exit_lobby() -> void:
	var game_controller = $"/root/GameController"
	
	if game_controller.is_host:
		var steam_connection = $"/root/SteamConnection"
		steam_connection.close_lobby()
		
	RunData.current_zone = 0
	RunData.reload_music = false
	var _error = get_tree().change_scene(MenuData.title_screen_scene)


func _on_game_mode_changed(_index):
	var game_controller = $"/root/GameController"
	game_controller.lobby_data["game_mode"] = game_mode_dropdown.selected
	update_selections()


func update_ready_toggle(is_ready:bool):
	var game_controller = $"/root/GameController"
	game_controller.on_mp_lobby_ready_changed(is_ready)


func _on_BackButton_pressed():
	exit_lobby()


func disable_options() -> void:
	game_mode_dropdown.disabled = true
	copy_host_toggle.disabled = true
	first_death_loss_toggle.disabled = true
	shared_gold_toggle.disabled = true
	material_count_slider._slider.editable = false
	enemy_count_slider._slider.editable = false
	enemy_hp_slider._slider.editable = false
	enemy_damage_slider._slider.editable = false
	enemy_speed_slider._slider.editable = false


func on_option_updated(_value) -> void:
	var game_controller = $"/root/GameController"
	if not game_controller.is_host:
		return
	
	game_controller.lobby_data["copy_host"] = copy_host_toggle.is_pressed()
	game_controller.lobby_data["first_death_loss"] = first_death_loss_toggle.is_pressed()
	game_controller.lobby_data["shared_gold"] = shared_gold_toggle.is_pressed()
	game_controller.lobby_data["material_count"] = material_count_slider._slider.get_value()
	game_controller.lobby_data["enemy_count"] = enemy_count_slider._slider.get_value()
	game_controller.lobby_data["enemy_hp"] = enemy_hp_slider._slider.get_value()
	game_controller.lobby_data["enemy_damage"] = enemy_damage_slider._slider.get_value()
	game_controller.lobby_data["enemy_speed"] = enemy_speed_slider._slider.get_value()
	
	should_send_lobby_update = true
	update_selections()
