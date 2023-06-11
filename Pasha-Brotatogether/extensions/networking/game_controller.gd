extends Node

# here they'll be keyed by steam user ids
var tracked_players = {}
var connection

# The id of this player, in direct ip connections this will be 1 for the host.
# in steam connections this will be a steam id against which a username can
# be queried
var self_peer_id

# True iff the user hosted the lobby
var is_host = false

var is_source_of_truth = true
var game_mode = ""

# A counter user to assign ids for game components
var id_count = 0

const GameStateController = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/networking/game_state_controller.gd")

const toggle_scene = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/ui/menus/pages/toggle.tscn")
const button_scene = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/ui/menus/pages/button.tscn")

var current_scene_name = ""
var run_updates = false
var back_to_lobby = false

var ready_toggle

var extra_enemies_next_wave = {}
var effects_next_wave = {}
var game_state_controller 

func _init():
	game_state_controller = GameStateController.new()
	game_state_controller.parent = self
	add_child(game_state_controller)

func _process(_delta):
	var scene_name = get_tree().get_current_scene().get_name()
	if game_mode == "shared" and is_source_of_truth:
		# TODO i can't seem to override Shop.gd because it errors trying to get
		# a RunData field, we'll do this gargbage instead.
		if scene_name != current_scene_name:
			if current_scene_name == "Shop":
				# First frame where we left the shop
				var wave_data = {"current_wave":RunData.current_wave, "mode":game_mode}
				send_start_game(wave_data)
	if scene_name != current_scene_name:
		if scene_name == "Shop":
			enter_async_shop()
			
	current_scene_name = scene_name

func enter_async_shop() -> void:
	if $"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer":
		$"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer".update_bought_items(tracked_players)
	if is_host:
		init_shop_go_button()
	else:
		$"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/GoButton".hide()
		$"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2".add_child(create_ready_toggle())

func create_extra_creatures_map() -> Dictionary:
	var extra_creatures_map = {}
	
	for player_id in tracked_players:
		extra_creatures_map[player_id] = tracked_players[player_id]["extra_enemies_next_wave"]
	return extra_creatures_map
	
func create_effects_map() -> Dictionary:
	var effects_map = {}
	
	for player_id in tracked_players:
		effects_map[player_id] = tracked_players[player_id]["effects"]
	
	return effects_map

func init_shop_go_button() -> void:
	var shop = get_tree().get_current_scene()
	var button = $"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/GoButton"
	
	button.disconnect("pressed", shop, "_on_GoButton_pressed")
	button.connect("pressed", self, "_on_GoButton_pressed")
	
	print_debug("updating go button")
	
	update_go_button()

func _on_GoButton_pressed()-> void:
	var shop = get_tree().get_current_scene()
	if shop._go_button_pressed:
		return 
	
	shop._go_button_pressed = true
	
	extra_enemies_next_wave = create_extra_creatures_map()
	effects_next_wave = create_effects_map()
	
	RunData.current_wave += 1
	MusicManager.tween(0)
	
	var wave_data = {"current_wave":RunData.current_wave, "mode":game_mode}	
	var extra_creatures_map = extra_enemies_next_wave
	
	wave_data["extra_enemies_next_wave"] = extra_creatures_map
	wave_data["effects"] = effects_next_wave
	
	send_start_game(wave_data)
	reset_extra_creatures()
	reset_ready_map()
	
#	RunData.effects["extra_enemies_next_wave"] = tracked_players[self_peer_id]["extra_enemies_next_wave"]
	
	var _error = get_tree().change_scene(MenuData.game_scene)

func start_game(game_info: Dictionary):
	reset_extra_creatures()
	reset_ready_map()
	
	if not is_host:
		is_source_of_truth = false
	
	game_mode = game_info.mode
	if game_mode == "shared":
		if game_info.current_wave == 1:
			RunData.weapons = []
			RunData.items = []
			RunData.effects = RunData.init_effects()
			RunData.current_character = null
			RunData.starting_weapon = null
			
			var lobby_info = game_info.lobby_info
			
			var character_data = load(lobby_info.character)
			var weapon_data = load(lobby_info.weapon)
			var danger = lobby_info.danger
			
			RunData.add_character(character_data)
			var _unused = RunData.add_weapon(weapon_data, true)
			RunData.add_starting_items_and_weapons()
			
			var character_difficulty = ProgressData.get_character_difficulty_info(RunData.current_character.my_id, RunData.current_zone)
			character_difficulty.difficulty_selected_value = danger
			RunData.init_elites_spawn()
			back_to_lobby = false
#		tracked_players = {}
#		RunData.current_wave = game_info.current_wave
		
		# TODO, I think i only need to do this in the first frame but i need to do the testing to 
		# make sure
#		RunData.add_character(load("res://items/characters/well_rounded/well_rounded_data.tres"))
#		var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/extensions/client_main.tscn")
		# MIGRATE reset_client_items()
		run_updates = true
		RunData.current_wave = game_info.current_wave
		if is_host:
			var _change_error = get_tree().change_scene(MenuData.game_scene)
		else:
			var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/extensions/client_main.tscn")
		
	elif game_mode == "async":
		if game_info.current_wave == 1:
			RunData.weapons = []
			RunData.items = []
			RunData.effects = RunData.init_effects()
			RunData.current_character = null
			RunData.starting_weapon = null
			
			var lobby_info = game_info.lobby_info
			
			var character_data = load(lobby_info.character)
			var weapon_data = load(lobby_info.weapon)
			var danger = lobby_info.danger
			
			RunData.add_character(character_data)
			var _unused = RunData.add_weapon(weapon_data, true)
			RunData.add_starting_items_and_weapons()
			
			var character_difficulty = ProgressData.get_character_difficulty_info(RunData.current_character.my_id, RunData.current_zone)
			character_difficulty.difficulty_selected_value = danger
			RunData.init_elites_spawn()
			back_to_lobby = false
			
		RunData.current_wave = game_info.current_wave
		if game_info.has("extra_enemies_next_wave"):
			extra_enemies_next_wave  = game_info.extra_enemies_next_wave
		if game_info.has("effects"):
			effects_next_wave = game_info.effects
		var _change_error = get_tree().change_scene(MenuData.game_scene)

func send_death() -> void:
	print_debug("sending death")
	if is_host:
		receive_death(self_peer_id)
	else:
		connection.send_death()

func receive_death(source_player_id:int) -> void:
	tracked_players[source_player_id]["dead"] = true
	if is_host:
		connection.send_tracked_players(tracked_players)
	if source_player_id != self_peer_id:
		check_win()

func check_win() -> void:
	var all_others_dead = true
	for tracked_player_id in tracked_players:
		if tracked_player_id == self_peer_id:
			continue
		var tracked_player = tracked_players[tracked_player_id]
		if not tracked_player.has("dead") or not tracked_player.dead:
			all_others_dead = false
	
	if all_others_dead:
		var main = $"/root/Main"
		main._is_run_won = true
		main.clean_up_room(false, main._is_run_lost, main._is_run_won)
		main._end_wave_timer.start()
		ProgressData.reset_run_state()

func send_bought_item(shop_item:Resource) -> void:
	if is_host:
		receive_bought_item(shop_item, self_peer_id)
	else:
		connection.send_bought_item(shop_item)
	
func receive_bought_item(shop_item:Resource, source_player_id:int) -> void:
	var effect_path = shop_item.effect.get_path()
	for player_id in tracked_players:
		if player_id != source_player_id:
			var effect = shop_item.effect
			if effect is WaveGroupData:
				if not tracked_players[player_id]["extra_enemies_next_wave"].has(effect_path):
					tracked_players[player_id]["extra_enemies_next_wave"][effect_path] = 0
				tracked_players[player_id]["extra_enemies_next_wave"][effect_path] = tracked_players[player_id]["extra_enemies_next_wave"][effect_path] + 1
			elif effect is Effect:
				if not tracked_players[player_id]["effects"].has(effect_path):
					tracked_players[player_id]["effects"][effect_path] = 0
				tracked_players[player_id]["effects"][effect_path] = tracked_players[player_id]["effects"][effect_path] + 1
	
	if is_host:
		connection.send_tracked_players(tracked_players)
	if $"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer":
		$"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer".update_bought_items(tracked_players)

func update_tracked_players(updated_tracked_players: Dictionary) -> void:
	# Actual Player state is updated elsewhere
	for player_id in updated_tracked_players:
		if tracked_players.has(player_id) and tracked_players[player_id].has("player"):
			updated_tracked_players[player_id]["player"] = tracked_players[player_id]["player"]
		else:
			updated_tracked_players[player_id].erase("player")
		
	tracked_players = updated_tracked_players
	if current_scene_name == "Shop":
		$"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer".update_bought_items(tracked_players)
	elif current_scene_name == "Main":
		update_health_ui()
		check_win()

func create_ready_toggle() -> Node:
	ready_toggle = toggle_scene.instance()
	ready_toggle.connect("pressed", self, "_on_ready_toggle")
	return ready_toggle

func _on_ready_toggle() -> void:
	connection.send_ready(ready_toggle.pressed)

func display_floating_text(text_info:Dictionary):
	if $"/root/ClientMain":
		$"/root/ClientMain/FloatingTextManager".display(text_info.value, text_info.position, text_info.color)

func display_hit_effect(effect_info: Dictionary):
	if $"/root/ClientMain/EffectsManager":
		var effects_manager = $"/root/ClientMain/EffectsManager"
		effects_manager.play_hit_particles(effect_info.position, effect_info.direction, effect_info.scale)
		effects_manager.play_hit_effect(effect_info.position, effect_info.direction, effect_info.scale)

func end_wave():
	run_updates = false
	game_state_controller.reset_client_items()
	
	print_debug("erasing keys??")
	for player_id in tracked_players:
		print_debug("erasing key: ", player_id)
		tracked_players[player_id].erase("player")

func send_ready(is_ready:bool) -> void:
	connection.send_ready(is_ready)

func send_game_state() -> void:
	connection.send_state(game_state_controller.get_game_state())

func send_start_game(game_info:Dictionary) -> void:
	connection.send_start_game(game_info)

func send_display_floating_text(text_info:Dictionary) -> void:
	connection.send_display_floating_text(text_info)

func send_display_hit_effect(effect_info: Dictionary) -> void:
	connection.send_display_hit_effect(effect_info)

func send_enemy_death(enemy_id:int) -> void:
	connection.send_enemy_death(enemy_id)

func send_end_wave() -> void:
	connection.send_end_wave()

func send_flash_enemy(enemy_id:int) -> void:
	connection.send_flash_enemy(enemy_id)

func send_flash_neutral(neutral_id:int) -> void:
	connection.send_flash_neutral(neutral_id)

func send_lobby_update(lobby_info:Dictionary) -> void:
	connection.send_lobby_update(lobby_info)

func receive_lobby_update(lobby_info:Dictionary) -> void:
	if current_scene_name == "MultiplayerLobby":
		$"/root/MultiplayerLobby".remote_update_lobby(lobby_info)
	
func send_client_position() -> void:
	if not tracked_players.has(self_peer_id) or not tracked_players[self_peer_id].has("player"):
		return
	var my_player = tracked_players[self_peer_id]["player"]
	var client_position = {}
	client_position["player"] = my_player.position
	client_position["id"] = self_peer_id
	client_position["movement"] = my_player._current_movement
	var weapons = []
	for weapon in my_player.current_weapons:
		var weapon_data = {}
		weapon_data["weapon_id"] = weapon.weapon_id
		weapon_data["position"] = weapon.sprite.position
		weapon_data["rotation"] = weapon.sprite.rotation
		weapon_data["hitbox_disabled"] = weapon._hitbox._collision.disabled
		weapons.push_back(weapon_data)
	client_position["weapons"] = weapons
	
	connection.send_client_position(client_position)

func update_client_position(client_position:Dictionary) -> void:
	if is_source_of_truth:
		var id = client_position.id
		if tracked_players.has(id):
			if tracked_players[id].has("player"):
				var player = tracked_players[id]["player"]
				player.position = client_position.player
				player.maybe_update_animation(client_position.movement, true)

func update_ready_state(sender_id, is_ready):
	if is_host:
		tracked_players[sender_id]["is_ready"] = is_ready
	if current_scene_name == "Shop":
		update_go_button()

func reset_ready_map():
	for player_id in tracked_players:
		tracked_players[player_id]["is_ready"] = false
		
func reset_extra_creatures():
	for player_id in tracked_players:
		tracked_players[player_id]["extra_enemies_next_wave"] = {}
		tracked_players[player_id]["effects"] = {}

func update_go_button():
	var should_enable = true
	print_debug("tracked players: ", tracked_players)
	for player_id in tracked_players:
		if player_id != self_peer_id and not tracked_players[player_id]["is_ready"]:
			should_enable = false
			break
	var shop_button = $"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/GoButton"
	if not should_enable:
		shop_button.disabled = true
	else:
		shop_button.disabled = false

func get_items_state() -> Dictionary:
	var main = $"/root/Main"
	var items = []
	for item in main._items_container.get_children():
		var item_data = {}

		item_data["id"]  = item.id
		item_data["scale_x"] = item.scale.x
		item_data["scale_y"] = item.scale.y
		item_data["position"] = item.global_position
		item_data["rotation"] = item.rotation
		item_data["push_back_destination"]  = item.push_back_destination

		# TODO we may want textures propagated
		items.push_back(item_data)
	return items





func get_projectiles_state() -> Dictionary:
	var main = $"/root/Main"
	var projectiles = []
	for child in main.get_children():
		if child is PlayerProjectile:
			var projectile_data = {}
			projectile_data["id"] = child.id
			projectile_data["filename"] = child.filename
			projectile_data["position"] = child.position
			projectile_data["global_position"] = child.global_position
			projectile_data["rotation"] = child.rotation

			projectiles.push_back(projectile_data)
	return projectiles

func receive_health_update(current_health:int, max_health:int, source_player_id:int) -> void:
	tracked_players[source_player_id]["max_health"] = max_health
	tracked_players[source_player_id]["current_health"] = current_health
	
	if is_host:
		connection.send_tracked_players(tracked_players)
	update_health_ui()

func update_health_ui() -> void:
	if current_scene_name == "Main":
		if $"/root/Main/UI/HealthTracker":
			$"/root/Main/UI/HealthTracker".update_health_bars(tracked_players)
	
func update_health(current_health:int, max_health:int) -> void:
	if is_host:
		receive_health_update(current_health, max_health, self_peer_id)
	else:
		connection.send_health_update(current_health, max_health)

func update_game_state(data: Dictionary) -> void:
	if run_updates:
		game_state_controller.update_game_state(data)

func enemy_death(enemy_id):
	game_state_controller.enemy_death(enemy_id)

func flash_enemy(enemy_id):
	game_state_controller.flash_enemy(enemy_id)

func flash_neutral(neutral_id):
	game_state_controller.flash_neutral(neutral_id)
