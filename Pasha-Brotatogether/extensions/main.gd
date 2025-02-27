extends "res://main.gd"

var ClientMovementBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_movement_behavior.gd")
var ClientAttackBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_attack_behavior.gd")

var steam_connection
var brotatogether_options
var in_multiplayer_game = false

var player_in_scene = [true, false, false, false]
var waiting_to_start_round = false

const SEND_RATE : float = 1.0 / 30.0
var send_timer = SEND_RATE
var my_player_index

var client_enemies = {}
var client_births = {}
var client_player_projectiles = {}

const ENTITY_BIRTH_SCENE = preload("res://entities/birth/entity_birth.tscn")


func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"
	in_multiplayer_game = brotatogether_options.in_multiplayer_game
	
	if in_multiplayer_game:
		steam_connection.connect("client_status_received", self, "_client_status_received")
		steam_connection.connect("host_starts_round", self, "_host_starts_round")
		steam_connection.connect("state_update", self, "_state_update")
		steam_connection.connect("client_position", self, "_update_player_position")
		
		my_player_index = steam_connection.get_my_index()
		
		call_deferred("multiplayer_ready")


func _physics_process(delta : float):
	if not in_multiplayer_game:
		return
	
	send_timer -= delta
	if send_timer <= 0.0:
		send_timer = SEND_RATE
		if steam_connection.is_host():
			_send_game_state()
		else:
			_send_client_position()


func _process(delta):
	if in_multiplayer_game:
		if waiting_to_start_round:
			if steam_connection.is_host():
				var all_players_entered = true
				for player_index in RunData.get_player_count():
					if not player_in_scene[player_index]:
						all_players_entered = false
						break
				if all_players_entered:
					waiting_to_start_round = false
					_wave_timer.start()
					steam_connection.send_round_start()


func _send_game_state() -> void:
	var state_dict = {}
	
	state_dict["WAVE_TIME"] = _wave_timer.time_left
	
	var players = []
	for player_index in _players.size():
		var player = _players[player_index]
		players.push_back(_dictionary_for_player(player))
	state_dict["PLAYERS"] = players
	
	var enemies = []
	for enemy in _entity_spawner.enemies:
		enemies.push_back(_dictionary_for_enemy(enemy))
	state_dict["ENEMIES"] = enemies
	
	state_dict["BATCHED_ENEMY_DEATHS"] = brotatogether_options.batched_enemy_deaths.duplicate()
	brotatogether_options.batched_enemy_deaths.clear()
	
	state_dict["BIRTHS"] = _host_births_array()
	state_dict["PLAYER_PROJECTILES"] = _host_player_projectiles_array()
	
	steam_connection.send_game_state(state_dict)


func _state_update(state_dict : Dictionary) -> void:
#	print_debug("received state ", state_dict)
	
	var wait_time = float(state_dict["WAVE_TIME"])
	if wait_time > 0:
		_wave_timer.start(wait_time)
	
	var players_array = state_dict["PLAYERS"]
	for player_index in players_array.size():
		_update_player_position(players_array[player_index], player_index)
	
	var enemies_array = state_dict["ENEMIES"]
	for enemy in enemies_array:
		_update_enemy(enemy)
	
	for enemy_id in state_dict["BATCHED_ENEMY_DEATHS"]:
		if client_enemies.has(enemy_id):
			client_enemies[enemy_id].die()
	
	_update_player_projectiles(state_dict["PLAYER_PROJECTILES"])
	_update_births(state_dict["BIRTHS"])


func _send_client_position() -> void:
	steam_connection.send_client_position(_dictionary_for_player(_players[my_player_index]))


func _dictionary_for_player(player) -> Dictionary:
	var position = player.position
	
	var player_dict = {
		"X_POS" : player.position.x,
		"Y_POS" : player.position.y,
		
		"MOVE_X" : player._current_movement.x,
		"MOVE_Y" : player._current_movement.y,
		
		"SPRITE_SCALE_X": player.sprite.scale.x 
	}
	
	var weapons_array : Array = []
	var weapons = player.current_weapons
	for weapon in weapons:
		var weapon_dict = {}
		
		weapon_dict["SPRITE_ROTATION"] = weapon.sprite.rotation
		weapon_dict["ROTATION"] = weapon.rotation
		weapon_dict["X_POS"] = weapon.sprite.position.x
		weapon_dict["Y_POS"] = weapon.sprite.position.y
		weapon_dict["IS_SHOOTING"] = weapon._is_shooting
		
		weapons_array.push_back(weapon_dict)
	player_dict["WEAPONS"] = weapons_array
	
	return player_dict


func _update_player_position(player_dict : Dictionary, player_index : int) -> void:
	if player_index != my_player_index:
		_players[player_index].position.x = player_dict["X_POS"]
		_players[player_index].position.y = player_dict["Y_POS"]
		
		_players[player_index].sprite.scale.x  = player_dict["SPRITE_SCALE_X"]
		
		_players[player_index]._current_movement.x  = player_dict["MOVE_X"]
		_players[player_index]._current_movement.y  = player_dict["MOVE_Y"]
		
		_players[player_index].update_animation(_players[player_index]._current_movement)
	
	if not steam_connection.is_host():
		var weapons_array = player_dict["WEAPONS"]
		for weapon_index in weapons_array.size():
			var weapon_dict = weapons_array[weapon_index]
			var weapon = _players[player_index].current_weapons[weapon_index]
			
			weapon.sprite.position.x = weapon_dict["X_POS"]
			weapon.sprite.position.y = weapon_dict["Y_POS"]
			weapon.sprite.rotation = weapon_dict["SPRITE_ROTATION"]
			weapon.rotation = weapon_dict["ROTATION"]
			weapon._is_shooting = weapon_dict["IS_SHOOTING"]


func _dictionary_for_enemy(enemy) -> Dictionary:
	var enemy_dict = {}
	
	enemy_dict["NETWORK_ID"] = enemy.network_id
	enemy_dict["RESOURCE_PATH"] = enemy.stats.resource_path
	enemy_dict["FILENAME"] = enemy.filename
	enemy_dict["X_POS"] = enemy.position.x
	enemy_dict["Y_POS"] = enemy.position.y
	enemy_dict["MOVE_X"] = enemy._current_movement.x
	enemy_dict["MOVE_Y"] = enemy._current_movement.y
	
	return enemy_dict


func _update_enemy(enemy_dict : Dictionary) -> void:
	var enemy_id = enemy_dict["NETWORK_ID"]
	if client_enemies.has(enemy_id):
		var enemy = client_enemies[enemy_id]
		
		enemy.position.x = enemy_dict["X_POS"]
		enemy.position.y = enemy_dict["Y_POS"]
		
		enemy._current_movement.x = enemy_dict["MOVE_X"]
		enemy._current_movement.y = enemy_dict["MOVE_Y"]
		
		enemy.call_deferred("update_animation", enemy._current_movement)
	else:
		call_deferred("spawn_enemy", enemy_dict)


func spawn_enemy(enemy_dict) -> void:
	var filename = enemy_dict["FILENAME"]
	var resource_path = enemy_dict["RESOURCE_PATH"]
	var enemy_id = enemy_dict["NETWORK_ID"]
	
	var enemy = load(filename).instance()
	
	var position : Vector2 = Vector2(enemy_dict["X_POS"], enemy_dict["Y_POS"])
	enemy.position = position
	enemy.stats = load(resource_path)
	
	client_enemies[enemy_id] = enemy
	
	var movement_behavior = enemy.get_node("MovementBehavior")
	enemy.remove_child(movement_behavior)
	var client_movement_behavior = ClientMovementBehavior.new()
	client_movement_behavior.set_name("MovementBehavior")
	enemy.add_child(client_movement_behavior, true)
	enemy._current_movement_behavior = client_movement_behavior
	
	var attack_behavior = enemy.get_node("AttackBehavior")
	enemy.remove_child(attack_behavior)
	var client_attack_behavior = ClientAttackBehavior.new()
	client_attack_behavior.set_name("AttackBehavior")
	enemy.add_child(client_attack_behavior, true)
	enemy._current_attack_behavior = client_attack_behavior
	
	_entities_container.add_child(enemy)


func multiplayer_ready():
	_wave_timer.stop()
	waiting_to_start_round = true


func _client_status_received(client_data : Dictionary, player_index : int) -> void:
	if waiting_to_start_round:
		if client_data["CURRENT_SCENE"] == "Main":
			player_in_scene[player_index] = true


func _host_starts_round() -> void:
	waiting_to_start_round = false
	_wave_timer.start()


func _on_WaveTimer_timeout() -> void:
	if in_multiplayer_game:
		print_debug("wave timer ended")
#		if steam_connection.is_host():
#			._on_WaveTimer_timeout()
		# TODO wave cleanup and stuff
		_end_wave_timer.start()
	else:
		._on_WaveTimer_timeout()


func _on_EndWaveTimer_timeout()->void :
	if in_multiplayer_game:
		print_debug("post-wave timer ended")
#		if steam_connection.is_host():
#			._on_EndWaveTimer_timeout()
		# TODO process upgrades and items
		_change_scene(RunData.get_shop_scene_path())
	else:
		._on_EndWaveTimer_timeout()


func _host_births_array() -> Array:
	var births_array = []
	
	for birth in _entity_spawner.births:
		var birth_dict = {}
		
		birth_dict["NETWORK_ID"] = birth.network_id
		
		birth_dict["X_POS"] = birth.global_position.x
		birth_dict["Y_POS"] = birth.global_position.y
		
		birth_dict["COLOR_R"] = birth.color.r
		birth_dict["COLOR_G"] = birth.color.g
		birth_dict["COLOR_B"] = birth.color.b
		birth_dict["COLOR_A"] = birth.color.a
		
		births_array.push_back(birth_dict)
	
	return births_array


func _update_births(births_array : Array) -> void:
	var current_births : Dictionary = {}
	
	for birth_dict in births_array:
		var network_id = birth_dict["NETWORK_ID"]
		current_births[network_id] = true
		
		var birth
		if client_births.has(network_id):
			birth = client_births[network_id]
		else:
			birth = ENTITY_BIRTH_SCENE.instance()
			birth.network_id = network_id
			_entities_container.add_child(birth)
			client_births[network_id] = birth
			birth.start()
		
		birth.color.r = birth_dict["COLOR_R"]
		birth.color.g = birth_dict["COLOR_G"]
		birth.color.b = birth_dict["COLOR_B"]
		birth.color.a = birth_dict["COLOR_A"]
		
		birth.global_position.x = birth_dict["X_POS"]
		birth.global_position.y = birth_dict["Y_POS"]
	
	for network_id in client_births:
		var old_birth = client_births[network_id]
		if not current_births.has(network_id):
			client_births.erase(network_id)
			old_birth.queue_free()


func _host_player_projectiles_array() -> Array:
	var player_projectiles_array = []
	var container_scene = Utils.get_scene_node()
	
	for child in container_scene.get_children():
		if child is PlayerProjectile:
			var projectile_dict = {}
			projectile_dict["NETWORK_ID"] = child.network_id
			projectile_dict["X_POS"] = child.global_position.x
			projectile_dict["Y_POS"] = child.global_position.y
			projectile_dict["ROTATION"] = child.rotation
			projectile_dict["FILENAME"] = child.filename
			player_projectiles_array.push_back(projectile_dict)
	return player_projectiles_array 


func _update_player_projectiles(player_projectiles_array : Array) -> void:
	var current_projectiles = {}
	
	for player_projectile_dict in player_projectiles_array:
		var network_id = player_projectile_dict["NETWORK_ID"]
		current_projectiles[network_id] = true
		
		if client_player_projectiles.has(network_id):
			var projectile = client_player_projectiles[network_id]
			
			projectile.global_position.x = player_projectile_dict["X_POS"]
			projectile.global_position.y = player_projectile_dict["Y_POS"]
			projectile.rotation = player_projectile_dict["ROTATION"]
		else:
			call_deferred("_spawn_player_projectile", player_projectile_dict)
	
	for network_id in client_player_projectiles:
		if not current_projectiles.has(network_id):
			client_player_projectiles[network_id].queue_free()
			client_player_projectiles.erase(network_id)


func _spawn_player_projectile(player_projectile_dict : Dictionary) -> void:
	var network_id = player_projectile_dict["NETWORK_ID"]
	var projectile = load(player_projectile_dict["FILENAME"]).instance()
	
	client_player_projectiles[network_id] = projectile
	
	projectile.global_position.x = player_projectile_dict["X_POS"]
	projectile.global_position.y = player_projectile_dict["Y_POS"]
	projectile.rotation = player_projectile_dict["ROTATION"]
	projectile.enable_physics_process = false
	projectile.weapon_stats = WeaponStats.new()
	Utils.get_scene_node().add_child(projectile)
