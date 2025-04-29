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
var client_enemy_projectiles = {}
var client_items = {}
var client_consumables = {}
var client_neutrals = {}
var client_structures = {}

const ENTITY_BIRTH_SCENE = preload("res://entities/birth/entity_birth.tscn")
const TREE_SCENE = preload("res://entities/units/neutral/tree.tscn")
const CLIENT_TURRET_STATS = preload("res://entities/structures/turret/turret_stats.tres")

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
	state_dict["ITEMS"] = _host_items_array()
	state_dict["CONSUMABLES"] = _host_consumables_array()
	state_dict["NEUTRALS"] = _host_neutrals_array()
	state_dict["STRUCTURES"] = _host_structures_array()
	state_dict["ENEMY_PROJECTILES"] = _host_enemy_projectiles_array()
	
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
			if not client_enemies[enemy_id].dead:
				client_enemies[enemy_id].die()
			client_enemies.erase(enemy_id)
	
	_update_player_projectiles(state_dict["PLAYER_PROJECTILES"])
	_update_births(state_dict["BIRTHS"])
	_update_items(state_dict["ITEMS"])
	_update_consumables(state_dict["CONSUMABLES"])
	_update_neutrals(state_dict["NEUTRALS"])
	_update_structures(state_dict["STRUCTURES"])
	_update_enemy_projectiles(state_dict["ENEMY_PROJECTILES"])


#func get_game_state() -> PoolByteArray:
#	var buffer = StreamPeerBuffer.new()
#
#	if "/root/Main":
#		var main = $"/root/Main"
#
#		if main:
#			get_players_state(buffer) ## DONE
#			get_enemies_state(buffer)  ## DONE
#			get_births_state(buffer) ## DONE
#			get_items_state(buffer) ## DONE
#			get_projectiles_state(buffer) ## DONE
#			get_consumables_state(buffer) ## DONE
#			get_neutrals_state(buffer) ## DONE
#			get_structures_state(buffer) ## DONE
#			get_enemy_projectiles(buffer) ## DONE
#			get_deaths(buffer) ## DONE
#			get_enemy_damages(buffer)
#			get_enemy_flashes(buffer)
#			get_batched_floating_text(buffer)
#			get_hit_effects(buffer)
#
#			buffer.put_float(main._wave_timer.time_left)
#			buffer.put_32(RunData.bonus_gold)
#
#	return buffer.data_array


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
	
	for birth in _births_container.get_children():
		var birth_dict = {}
		
		birth_dict["NETWORK_ID"] = birth.network_id
		
		birth_dict["X_POS"] = birth.global_position.x
		birth_dict["Y_POS"] = birth.global_position.y
		
		birth_dict["COLOR_R"] = birth._color.r
		birth_dict["COLOR_G"] = birth._color.g
		birth_dict["COLOR_B"] = birth._color.b
		birth_dict["COLOR_A"] = birth._color.a
		birth_dict["TYPE"] = birth.type
		
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
			_births_container.add_child(birth)
			client_births[network_id] = birth
			birth.start(birth_dict["TYPE"], ENTITY_BIRTH_SCENE, Vector2(birth_dict["X_POS"], birth_dict["Y_POS"]))
		
		# TODO, I don't think we need these colors anymore
		birth._color.r = birth_dict["COLOR_R"]
		birth._color.g = birth_dict["COLOR_G"]
		birth._color.b = birth_dict["COLOR_B"]
		birth._color.a = birth_dict["COLOR_A"]
	
	for network_id in client_births:
		var old_birth = client_births[network_id]
		if not current_births.has(network_id):
			client_births.erase(network_id)
			old_birth.queue_free()


func _host_player_projectiles_array() -> Array:
	var player_projectiles_array = []
	
	for child in _player_projectiles.get_children():
		if child is PlayerProjectile and child._hitbox.active:
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
			if is_instance_valid(client_player_projectiles[network_id]):
				client_player_projectiles[network_id].queue_free()
			client_player_projectiles.erase(network_id)


func _spawn_player_projectile(player_projectile_dict : Dictionary) -> void:
	var network_id = player_projectile_dict["NETWORK_ID"]
	var projectile = load(player_projectile_dict["FILENAME"]).instance()
	
	client_player_projectiles[network_id] = projectile
	
	projectile.global_position.x = player_projectile_dict["X_POS"]
	projectile.global_position.y = player_projectile_dict["Y_POS"]
	projectile.spawn_position.x = player_projectile_dict["X_POS"]
	projectile.spawn_position.y = player_projectile_dict["Y_POS"]

	# The projectile will despawn if max_range is too low, the host will 
	# erase the projectile at the right time so set max range very high to
	# disable client-side logic in this regard.
	projectile._max_range = 9999
 
	projectile.rotation = player_projectile_dict["ROTATION"]

	_player_projectiles.add_child(projectile)

	projectile.set_physics_process(false)
	projectile.show()


func _host_items_array() -> Array:
	var items_array : Array = []
	for item in _active_golds:
		var item_dict = {}
		item_dict["NETWORK_ID"] = item.network_id
		item_dict["X_POS"] = item.global_position.x
		item_dict["Y_POS"] = item.global_position.y
		item_dict["X_SCALE"] = item.scale.x
		item_dict["Y_SCALE"] = item.scale.y
		items_array.push_back(item_dict)
	return items_array


func _update_items(items_array : Array) -> void:
	var current_items = {}
	
	for item_dict in items_array:
		var network_id = item_dict["NETWORK_ID"]
		current_items[network_id] = true
		if client_items.has(network_id):
			var item = client_items[network_id]
			item.global_position.x = item_dict["X_POS"]
			item.global_position.y = item_dict["Y_POS"]
		else:
			call_deferred("_spawn_item", item_dict)
	
	for network_id in client_items:
		if not current_items.has(network_id):
			client_items[network_id].queue_free()
			client_items.erase(network_id)


func _spawn_item(item_dict : Dictionary) -> void:
	var network_id = item_dict["NETWORK_ID"]
	var gold = gold_scene.instance()
	gold.set_texture(gold_sprites[Utils.randi() % 11])
	gold.scale.x = item_dict["X_SCALE"]
	gold.scale.y = item_dict["Y_SCALE"]
	_materials_container.add_child(gold)
	_active_golds.push_back(gold)
	client_items[network_id] = gold
	gold.call_deferred("show")


func _host_consumables_array() -> Array:
	var consumables_array = []
	
	for consumable in _consumables_container.get_children():
		if consumable.visible:
			var consumable_dict = {}
			consumable_dict["NETWORK_ID"] = consumable.network_id
			consumable_dict["X_POS"] = consumable.global_position.x
			consumable_dict["Y_POS"] = consumable.global_position.y
			consumable_dict["LOAD_PATH"] = consumable.consumable_data.icon.load_path
			consumables_array.push_back(consumable_dict)
	
	return consumables_array


func _update_consumables(consumables_array : Array) -> void:
	var current_consumables = {}
	
	for consumable_dict in consumables_array:
		var network_id = consumable_dict["NETWORK_ID"]
		current_consumables[network_id] = true
		if client_consumables.has(network_id):
			var consumable = client_consumables[network_id]
			consumable.global_position.x = consumable_dict["X_POS"]
			consumable.global_position.y = consumable_dict["Y_POS"]
		else:
			call_deferred("_spawn_consumable", consumable_dict)
	
	for network_id in client_consumables:
		if not current_consumables.has(network_id):
			client_consumables[network_id].queue_free()
			client_consumables.erase(network_id)


func _spawn_consumable(consumable_dict : Dictionary) -> void:
	var consumable:Consumable = get_node_from_pool(consumable_scene.resource_path)
	if consumable == null:
		consumable = consumable_scene.instance()
		_consumables_container.add_child(consumable)
	
	var file_path = consumable_dict["LOAD_PATH"]
	consumable.set_texture(load(file_path))
	consumable.global_position.x = consumable_dict["X_POS"]
	consumable.global_position.y = consumable_dict["Y_POS"]
	consumable.call_deferred("show")
	client_consumables[consumable_dict["NETWORK_ID"]] = consumable


func _host_neutrals_array() -> Array:
	var neutrals_array = []
	
	for neutral in _entity_spawner.neutrals:
		var neutral_dict = {}
		neutral_dict["NETWORK_ID"] = neutral.network_id
		neutral_dict["X_POS"] = neutral.global_position.x
		neutral_dict["Y_POS"] = neutral.global_position.y
		neutrals_array.push_back(neutral_dict)
	
	return neutrals_array


func _update_neutrals(neutrals_array : Array) -> void:
	var current_neutrals = {}
	
	for neutral_dict in neutrals_array:
		var network_id = neutral_dict["NETWORK_ID"]
		current_neutrals[network_id] = true
		if client_neutrals.has(network_id):
			var neutral = client_neutrals[network_id]
			neutral.global_position.x = neutral_dict["X_POS"]
			neutral.global_position.y = neutral_dict["Y_POS"]
		else:
			call_deferred("_spawn_neutral", neutral_dict)
	
	for network_id in client_neutrals:
		if not network_id in current_neutrals:
			client_neutrals[network_id].queue_free()
			client_neutrals.erase(network_id)


func _spawn_neutral(neutral_dict : Dictionary) -> void:
	var neutral = TREE_SCENE.instance()
	neutral.global_position.x = neutral_dict["X_POS"]
	neutral.global_position.y = neutral_dict["Y_POS"]
	
	client_neutrals[neutral_dict["NETWORK_ID"]] = neutral
	
	Utils.get_scene_node().add_child(neutral)


func _host_structures_array() -> Array:
	var structures_array = []
	
	for structure in _entity_spawner.structures:
		var structure_dict = {}
		
		structure_dict["NETWORK_ID"] = structure.network_id
		structure_dict["FILENAME"] = structure.filename
		structure_dict["X_POS"] = structure.position.x
		structure_dict["Y_POS"] = structure.position.y
		structures_array.push_back(structure_dict)
		
	return structures_array


func _update_structures(structures_array : Array) -> void:
	var current_structures = {}
	
	for structure_dict in structures_array:
		var network_id = structure_dict["NETWORK_ID"]
		current_structures[network_id] = true
		if client_structures.has(network_id):
			var structure = client_structures[network_id]
		else:
			call_deferred("_spawn_structure", structure_dict)
	
	for network_id in client_structures:
		if not network_id in current_structures:
			client_structures[network_id].queue_free()
			client_structures.erase(network_id)


func _spawn_structure(structure_dict : Dictionary) -> void:
	var filename = structure_dict["FILENAME"]
	var structure = load(filename).instance()
	
	structure.position.x = structure_dict["X_POS"]
	structure.position.y = structure_dict["Y_POS"]
	
	structure.stats = CLIENT_TURRET_STATS
	
	client_structures[structure_dict["NETWORK_ID"]] = structure
	
	Utils.get_scene_node().add_child(structure)


func _host_enemy_projectiles_array() -> Array:
	var enemy_projectiles_array = []
	
	for enemy_projectile in _enemy_projectiles.get_children():
		if enemy_projectile is Projectile and enemy_projectile._hitbox.active:
			var projectile_dict = {}
			projectile_dict["NETWORK_ID"] = enemy_projectile.network_id
			projectile_dict["X_POS"] = enemy_projectile.global_position.x
			projectile_dict["Y_POS"] = enemy_projectile.global_position.y
			projectile_dict["ROTATION"] = enemy_projectile.rotation
			projectile_dict["FILENAME"] = enemy_projectile.filename
			enemy_projectiles_array.push_back(projectile_dict)
	return enemy_projectiles_array


func _update_enemy_projectiles(enemy_projectiles_array : Array) -> void:
	var current_enemy_projectiles = {}
	for enemy_projectile_dict in enemy_projectiles_array:
		var network_id = enemy_projectile_dict["NETWORK_ID"]
		current_enemy_projectiles[network_id] = true
		
		if client_enemy_projectiles.has(network_id):
			var enemy_projectile = client_enemy_projectiles[network_id]
			
			enemy_projectile.global_position.x = enemy_projectile_dict["X_POS"]
			enemy_projectile.global_position.y = enemy_projectile_dict["Y_POS"]
			enemy_projectile.rotation = enemy_projectile_dict["ROTATION"]
		else:
			call_deferred("_spawn_enemy_projectile", enemy_projectile_dict)
	
	for network_id in client_enemy_projectiles:
		if not current_enemy_projectiles.has(network_id):
			if is_instance_valid(client_enemy_projectiles[network_id]):
				client_enemy_projectiles[network_id].queue_free()
			client_enemy_projectiles.erase(network_id)


func _spawn_enemy_projectile(enemy_projectile_dict : Dictionary) -> void:
	var network_id = enemy_projectile_dict["NETWORK_ID"]
	var enemy_projectile = load(enemy_projectile_dict["FILENAME"]).instance()
	client_enemy_projectiles[network_id] = enemy_projectile
	
	enemy_projectile.global_position.x = enemy_projectile_dict["X_POS"]
	enemy_projectile.global_position.y = enemy_projectile_dict["Y_POS"]
	
	enemy_projectile.spawn_position.x = enemy_projectile_dict["X_POS"]
	enemy_projectile.spawn_position.y = enemy_projectile_dict["Y_POS"]
	
	enemy_projectile._max_range = 9999
	enemy_projectile.rotation = enemy_projectile_dict["ROTATION"]
	
	_enemy_projectiles.add_child(enemy_projectile)
	_enemy_projectiles.set_physics_process(false)
	_enemy_projectiles.show()
