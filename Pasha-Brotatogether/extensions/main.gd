extends "res://main.gd"

var ClientMovementBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_movement_behavior.gd")
var ClientAttackBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_attack_behavior.gd")
var DataNode = load("res://mods-unpacked/Pasha-Brotatogether/data_node.gd")

var steam_connection
var brotatogether_options
var in_multiplayer_game = false

# If true, the steam logic will be skipped to avoid duplicate rpc chains.
var is_self_call = false

var player_in_scene = [true, false, false, false]
var waiting_to_start_round = false

const SEND_RATE : float = 1.0 / 30.0
var send_timer = SEND_RATE
var my_player_index

var client_players = {}
var client_enemies = {}
var client_births = {}
var client_player_projectiles = {}
var client_enemy_projectiles = {}
var client_items = {}
var client_consumables = {}
var client_neutrals = {}
var client_structures = {}

var server_player_projectile_ids = {}
var server_enemy_projectile_ids = {}

const ENTITY_BIRTH_SCENE = preload("res://entities/birth/entity_birth.tscn")
const TREE_SCENE = preload("res://entities/units/neutral/tree.tscn")
const CLIENT_TURRET_STATS = preload("res://entities/structures/turret/turret_stats.tres")
const ENABLE_DEBUG = true

var debug_frame_counter : int = 0

# This is currently a half-completed attempt ot shrink some of the overhead
# in messaging.  With a bit of testing, the gains weren't that great given 
# compression so it may not get done.
enum EntityState {
	ENTITY_STATE_NETWORK_ID,
	
	ENTITY_STATE_X_POS,
	ENTITY_STATE_Y_POS,
	ENTITY_STATE_X_MOVE,
	ENTITY_STATE_Y_MOVE,
	ENTITY_STATE_CURRENT_HP,
	ENTITY_STATE_MAX_HP,
	ENTITY_STATE_SPRITE_SCALE,
	
	# Player-specific entity state.
	ENTITY_STATE_PLAYER_GOLD,
	ENTITY_STATE_PLAYER_CURRENT_XP,
	ENTITY_STATE_PLAYER_NEXT_LEVEL_XP,
	ENTITY_STATE_PLAYER_NUM_UPGRADES,
	ENTITY_STATE_PLAYER_WEAPONS,
}

enum WeaponState {
	WEAPON_STATE_X_POS,
	WEAPON_STATE_Y_POS,
	WEAPON_STATE_ROTATION,
	WEAPON_STATE_SPRITE_ROTATION,
	WEAPON_STATE_IS_SHOOTING,
}

enum ProjectileState {
	PROJECTILE_STATE_NETWORK_ID,
	
	PROJECTILE_STATE_X_POS,
	PROJECTILE_STATE_Y_POS,
	PROJECTILE_STATE_ROTATION,
	PROJECTILE_STATE_FILENAME,
}



func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"
	in_multiplayer_game = brotatogether_options.in_multiplayer_game
	
	if in_multiplayer_game:
		steam_connection.connect("client_status_received", self, "_client_status_received")
		steam_connection.connect("host_starts_round", self, "_host_starts_round")
		steam_connection.connect("state_update", self, "_state_update")
		steam_connection.connect("client_position", self, "_update_player_position")
		steam_connection.connect("client_menu_focus", self, "_update_client_focus")
		
		steam_connection.connect("client_main_scene_reroll_button_pressed", self, "_client_reroll_button_pressed")
		steam_connection.connect("client_main_scene_choose_upgrade_pressed", self, "_client_choose_upgrade_button_pressed")
		steam_connection.connect("client_main_scene_take_button_pressed", self, "_client_take_button_pressed")
		steam_connection.connect("client_main_scene_discard_button_pressed", self, "_client_discard_button_pressed")
		
		steam_connection.connect("host_entered_shop", self, "_host_entered_shop")
		
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


func _process(_delta):
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
		players.push_back(_dictionary_for_player(player, player_index))
	state_dict["PLAYERS"] = players
	
	var enemies = []
	for enemy in _entity_spawner.enemies:
		enemies.push_back(_dictionary_for_enemy(enemy))
	state_dict["ENEMIES"] = enemies
	
	state_dict["BATCHED_ENEMY_DEATHS"] = brotatogether_options.batched_enemy_deaths.duplicate()
	brotatogether_options.batched_enemy_deaths.clear()
	
	state_dict["BATCHED_HIT_EFFECTS"] = brotatogether_options.batched_hit_effects.duplicate()
	brotatogether_options.batched_hit_effects.clear()
	
	state_dict["BATCHED_HIT_PARTICLES"] = brotatogether_options.batched_hit_particles.duplicate()
	brotatogether_options.batched_hit_particles.clear()
	
	state_dict["BATCHED_FLOATING_TEXT"] = brotatogether_options.batched_floating_text.duplicate()
	brotatogether_options.batched_floating_text.clear()
	
	state_dict["BATCHED_UNIT_FLASHES"] = brotatogether_options.batched_unit_flashes.duplicate()
	brotatogether_options.batched_unit_flashes.clear()
	
	state_dict["BIRTHS"] = _host_births_array()
	state_dict["PLAYER_PROJECTILES"] = _host_player_projectiles_array()
	state_dict["ITEMS"] = _host_items_array()
	state_dict["CONSUMABLES"] = _host_consumables_array()
	state_dict["NEUTRALS"] = _host_neutrals_array()
	state_dict["STRUCTURES"] = _host_structures_array()
	state_dict["ENEMY_PROJECTILES"] = _host_enemy_projectiles_array()
	state_dict["UPGRADE_MENU_STATUS"] = _host_menu_status()
	
	if ENABLE_DEBUG:
		var size_by_key = {}
		var big_enough_to_show = false
		for key in state_dict:
			var compressed_data: PoolByteArray = var2bytes(state_dict[key]).compress(File.COMPRESSION_GZIP)
			var compressed_size = compressed_data.size()
			if compressed_size > 200:
				big_enough_to_show = true
				if state_dict[key] is Array:
					size_by_key[key] = "%d (%.1f) " % [compressed_size, compressed_size / state_dict[key].size()]
				else:
					size_by_key[key] = compressed_size
		if big_enough_to_show:
			print_debug(size_by_key)
	
	steam_connection.send_game_state(state_dict)


func _state_update(state_dict : Dictionary) -> void:	
	var start_time : int = Time.get_ticks_usec()
	var before : int
#	print_debug("received state ", state_dict)
	
	before = Time.get_ticks_usec()
	var wait_time = float(state_dict["WAVE_TIME"])
	if wait_time > 0:
		_wave_timer.start(wait_time)
	var wave_timer_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	var players_array = state_dict["PLAYERS"]
	for player_index in players_array.size():
		_update_player_position(players_array[player_index], player_index)
	var player_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	var enemies_array = state_dict["ENEMIES"]
	for enemy in enemies_array:
		_update_enemy(enemy)
	var enemies_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	for enemy_id in state_dict["BATCHED_ENEMY_DEATHS"]:
		if client_enemies.has(enemy_id):
			if not client_enemies[enemy_id].dead:
				client_enemies[enemy_id].die()
			client_enemies.erase(enemy_id)
	var enemy_deaths_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	for flashing_unit_id in state_dict["BATCHED_UNIT_FLASHES"]:
		var flashing_unit
		if client_enemies.has(flashing_unit_id):
			flashing_unit = client_enemies[flashing_unit_id]
		elif client_players.has(flashing_unit_id):
			flashing_unit = client_players[flashing_unit_id]
		elif client_neutrals.has(flashing_unit_id):
			flashing_unit = client_neutrals[flashing_unit_id]
		if flashing_unit and is_instance_valid(flashing_unit):
			flashing_unit.flash()
	var flashing_units_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	_update_player_projectiles(state_dict["PLAYER_PROJECTILES"])
	var player_projectiles_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	_update_births(state_dict["BIRTHS"])
	var births_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	_update_items(state_dict["ITEMS"])
	var items_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	_update_consumables(state_dict["CONSUMABLES"])
	var consumables_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	_update_neutrals(state_dict["NEUTRALS"])
	var neutrals_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	_update_structures(state_dict["STRUCTURES"])
	var structures_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	_update_enemy_projectiles(state_dict["ENEMY_PROJECTILES"])
	var enemy_projectiles_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	_update_batched_hit_effects(state_dict["BATCHED_HIT_EFFECTS"])
	var enemy_hit_effects_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	_update_batched_hit_particles(state_dict["BATCHED_HIT_PARTICLES"])
	var enemy_hit_particles_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	_update_batched_floating_text(state_dict["BATCHED_FLOATING_TEXT"])
	var floating_text_update_time = Time.get_ticks_usec() - before
	
	before = Time.get_ticks_usec()
	_update_menu(state_dict["UPGRADE_MENU_STATUS"])
	var menu_update_time = Time.get_ticks_usec() - before
	
	if ENABLE_DEBUG:
		var end_time : int = Time.get_ticks_usec()
		var elapsed_time = end_time - start_time
		debug_frame_counter += 1
		if debug_frame_counter % 100 == 0 || elapsed_time > 1000:
			print_debug("state update time: ", elapsed_time)
			print_debug(wave_timer_update_time, " ", player_update_time, " ", enemies_update_time, " ", enemy_deaths_update_time, " ", flashing_units_update_time, " ", player_projectiles_update_time, " ", births_update_time, " ", items_update_time, " ", consumables_update_time, " ", neutrals_update_time, " ", structures_update_time, " ", enemy_projectiles_update_time, " ", enemy_hit_effects_update_time, " ", enemy_hit_particles_update_time, " ", floating_text_update_time, " ", menu_update_time)


func _input(event) -> void: 
	if not ENABLE_DEBUG:
		return
	if event is InputEventKey:
		if event.scancode == KEY_F1:
#			on_levelled_up(0)
			var consumable = consumable_scene.instance()
			var consumable_to_spawn = load("res://items/consumables/item_box/item_box_data.tres")
			consumable.consumable_data = consumable_to_spawn
			consumable.set_texture(consumable_to_spawn.icon)
			on_consumable_picked_up(consumable , 0)


func _send_client_position() -> void:
	var in_postwave_menu = _coop_upgrades_ui.visible
	if in_postwave_menu:
		var player_container = _coop_upgrades_ui._get_player_container(my_player_index)
		var focus_string = _string_for_menu_focus(player_container)
		steam_connection.send_client_menu_focus(
			{
				"FOCUS" : focus_string
			}
		)
	else:
		steam_connection.send_client_position(_dictionary_for_player(_players[my_player_index], my_player_index))


func _dictionary_for_player(player, player_index) -> Dictionary:
	var player_dict = {
		EntityState.ENTITY_STATE_NETWORK_ID : player.network_id,
		
		EntityState.ENTITY_STATE_X_POS : player.position.x,
		EntityState.ENTITY_STATE_Y_POS : player.position.y,
		
		EntityState.ENTITY_STATE_X_MOVE : player._current_movement.x,
		EntityState.ENTITY_STATE_Y_MOVE : player._current_movement.y,
		
		EntityState.ENTITY_STATE_SPRITE_SCALE: player.sprite.scale.x,
	}
	
	var weapons_array : Array = []
	var weapons = player.current_weapons
	for weapon in weapons:
		var weapon_dict = {}
		
		weapon_dict[WeaponState.WEAPON_STATE_SPRITE_ROTATION] = weapon.sprite.rotation
		weapon_dict[WeaponState.WEAPON_STATE_ROTATION] = weapon.rotation
		weapon_dict[WeaponState.WEAPON_STATE_X_POS] = weapon.sprite.position.x
		weapon_dict[WeaponState.WEAPON_STATE_Y_POS] = weapon.sprite.position.y
		weapon_dict[WeaponState.WEAPON_STATE_IS_SHOOTING] = weapon._is_shooting
		
		weapons_array.push_back(weapon_dict)
	player_dict[EntityState.ENTITY_STATE_PLAYER_WEAPONS] = weapons_array
	
	if steam_connection.is_host():
		player_dict[EntityState.ENTITY_STATE_PLAYER_GOLD] = RunData.players_data[player_index].gold
		player_dict[EntityState.ENTITY_STATE_PLAYER_CURRENT_XP] = RunData.players_data[player_index].current_xp
		player_dict[EntityState.ENTITY_STATE_PLAYER_NEXT_LEVEL_XP] = RunData.get_next_level_xp_needed(player_index)
		player_dict[EntityState.ENTITY_STATE_CURRENT_HP] = player.current_stats.health
		player_dict[EntityState.ENTITY_STATE_MAX_HP] = player.max_stats.health
		
		var things_to_process = _things_to_process_player_containers[player_index]
		player_dict[EntityState.ENTITY_STATE_PLAYER_NUM_UPGRADES] = things_to_process.upgrades._elements.size()
		
	return player_dict


func _update_player_position(player_dict : Dictionary, player_index : int) -> void:
	var player = _players[player_index]
	var network_id = player_dict[EntityState.ENTITY_STATE_NETWORK_ID]
	
	if not client_players.has(network_id):
		client_players[network_id] = player
	
	if player_index != my_player_index:
		if player.dead:
			return
		player.position.x = player_dict[EntityState.ENTITY_STATE_X_POS]
		player.position.y = player_dict[EntityState.ENTITY_STATE_Y_POS]
		
		player.sprite.scale.x  = player_dict[EntityState.ENTITY_STATE_SPRITE_SCALE]
		
		player._current_movement.x  = player_dict[EntityState.ENTITY_STATE_X_MOVE]
		player._current_movement.y  = player_dict[EntityState.ENTITY_STATE_Y_MOVE]
		
		player.update_animation(_players[player_index]._current_movement)
	
	if not steam_connection.is_host():
		var current_xp = player_dict[EntityState.ENTITY_STATE_PLAYER_CURRENT_XP]
		var next_level_xp = player_dict[EntityState.ENTITY_STATE_PLAYER_NEXT_LEVEL_XP]
		RunData.players_data[player_index].current_xp = current_xp
		RunData.emit_signal("xp_added", current_xp, next_level_xp, player_index)
		
		var current_hp = player_dict[EntityState.ENTITY_STATE_CURRENT_HP]
		var max_hp = player_dict[EntityState.ENTITY_STATE_MAX_HP]
		var should_send_hp_signal = false
		if current_hp != player.current_stats.health:
			should_send_hp_signal = true
		player.current_stats.health = current_hp
		if max_hp != player.max_stats.health:
			should_send_hp_signal = true
		player.max_stats.health = max_hp
		if should_send_hp_signal:
			player.emit_signal("health_updated", player, player.current_stats.health, player.max_stats.health)
		
		var current_gold = player_dict[EntityState.ENTITY_STATE_PLAYER_GOLD]
		RunData.players_data[player_index].gold = current_gold
		RunData.emit_signal("gold_changed", current_gold, player_index)
		
		var things_to_process = _things_to_process_player_containers[player_index]
		if player_dict[EntityState.ENTITY_STATE_PLAYER_NUM_UPGRADES] > things_to_process.upgrades._elements.size():
			things_to_process.upgrades.add_element(ItemService.get_icon("icon_upgrade_to_process"), 1)
		
		var weapons_array = player_dict[EntityState.ENTITY_STATE_PLAYER_WEAPONS]
		for weapon_index in weapons_array.size():
			var weapon_dict = weapons_array[weapon_index]
			var weapon = player.current_weapons[weapon_index]
			
			weapon.sprite.position.x = weapon_dict[WeaponState.WEAPON_STATE_X_POS]
			weapon.sprite.position.y = weapon_dict[WeaponState.WEAPON_STATE_Y_POS]
			weapon.sprite.rotation = weapon_dict[WeaponState.WEAPON_STATE_SPRITE_ROTATION]
			weapon.rotation = weapon_dict[WeaponState.WEAPON_STATE_ROTATION]
			weapon._is_shooting = weapon_dict[WeaponState.WEAPON_STATE_IS_SHOOTING]


func _dictionary_for_enemy(enemy) -> Dictionary:
	var enemy_dict = {}
	
	enemy_dict["NETWORK_ID"] = enemy.network_id
	enemy_dict["RESOURCE_PATH"] = enemy.stats.resource_path
	enemy_dict["FILENAME"] = enemy.filename
	enemy_dict["X_POS"] = enemy.position.x
	enemy_dict["Y_POS"] = enemy.position.y
	enemy_dict["MOVE_X"] = enemy._current_movement.x
	enemy_dict["MOVE_Y"] = enemy._current_movement.y
	
	enemy_dict["MODULATE_A"] = enemy.sprite.self_modulate.a8
	enemy_dict["MODULATE_R"] = enemy.sprite.self_modulate.r8
	enemy_dict["MODULATE_G"] = enemy.sprite.self_modulate.g8
	enemy_dict["MODULATE_B"] = enemy.sprite.self_modulate.b8
	
	return enemy_dict


func _update_enemy(enemy_dict : Dictionary) -> void:
	var enemy_id = enemy_dict["NETWORK_ID"]
	if client_enemies.has(enemy_id):
		var enemy = client_enemies[enemy_id]
		
		enemy.position.x = enemy_dict["X_POS"]
		enemy.position.y = enemy_dict["Y_POS"]
		
		enemy._current_movement.x = enemy_dict["MOVE_X"]
		enemy._current_movement.y = enemy_dict["MOVE_Y"]
		
		var modulate_a = enemy_dict["MODULATE_A"]
		var modulate_r = enemy_dict["MODULATE_R"]
		var modulate_g = enemy_dict["MODULATE_G"]
		var modulate_b = enemy_dict["MODULATE_B"]
		
		enemy.sprite.self_modulate = Color8(modulate_r, modulate_g, modulate_b, modulate_a)
		
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
		if steam_connection.is_host():
			._on_WaveTimer_timeout()
			return
		else:
			_ui_dim_screen.dim()
			_wave_cleared_label.hide()
			_wave_timer_label.hide()
			_hud.hide()
			
			_coop_upgrades_ui.propagate_call("set_process_input", [true])
			DebugService.log_data("_on_EndWaveTimer_timeout")
			SoundManager.clear_queue()
			SoundManager2D.clear_queue()
			InputService.set_gamepad_echo_processing(true)
			_cleaning_up = true
			
			for player in _players:
				if is_instance_valid(player):
					player._can_move = false
					player.set_physics_process(false)
	else:
		._on_WaveTimer_timeout()


func _on_EndWaveTimer_timeout()->void :
	if in_multiplayer_game:
		if steam_connection.is_host():
			._on_EndWaveTimer_timeout()
	else:
		._on_EndWaveTimer_timeout()


func _host_births_array() -> Array:
	var births_array = []
	
	for birth in _births_container.get_children():
		if birth._collision_shape.disabled:
			continue
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
			var network_id
			if server_player_projectile_ids.has(child):
				network_id = server_player_projectile_ids[child]
			else:
				network_id = brotatogether_options.current_network_id
				brotatogether_options.current_network_id = brotatogether_options.current_network_id + 1
				server_player_projectile_ids[child] = network_id
			
			projectile_dict["NETWORK_ID"] = network_id
			projectile_dict["X_POS"] = child.position.x
			projectile_dict["Y_POS"] = child.position.y
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
			
			projectile.position.x = player_projectile_dict["X_POS"]
			projectile.position.y = player_projectile_dict["Y_POS"]
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
	
	projectile.position.x = player_projectile_dict["X_POS"]
	projectile.position.y = player_projectile_dict["Y_POS"]
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
	var consumable = get_node_from_pool(consumable_scene.resource_path)
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
			
			structure.position.x = structure_dict["X_POS"]
			structure.position.y = structure_dict["Y_POS"]
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
			var network_id
			if server_enemy_projectile_ids.has(enemy_projectile):
				network_id = server_enemy_projectile_ids[enemy_projectile]
			else:
				network_id = brotatogether_options.current_network_id
				brotatogether_options.current_network_id = brotatogether_options.current_network_id + 1
				server_enemy_projectile_ids[enemy_projectile] = network_id
			
			projectile_dict[ProjectileState.PROJECTILE_STATE_NETWORK_ID] = network_id
			projectile_dict[ProjectileState.PROJECTILE_STATE_X_POS] = enemy_projectile.global_position.x
			projectile_dict[ProjectileState.PROJECTILE_STATE_Y_POS] = enemy_projectile.global_position.y
			projectile_dict[ProjectileState.PROJECTILE_STATE_ROTATION] = enemy_projectile.rotation
			projectile_dict[ProjectileState.PROJECTILE_STATE_FILENAME] = enemy_projectile.filename
			enemy_projectiles_array.push_back(projectile_dict)
	return enemy_projectiles_array


func _update_enemy_projectiles(enemy_projectiles_array : Array) -> void:
	var current_enemy_projectiles = {}
	for enemy_projectile_dict in enemy_projectiles_array:
		var network_id = enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_NETWORK_ID]
		current_enemy_projectiles[network_id] = true
		
		if client_enemy_projectiles.has(network_id):
			var enemy_projectile = client_enemy_projectiles[network_id]
			
			if not is_instance_valid(enemy_projectile):
				continue
			
			enemy_projectile.position.x = enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_X_POS]
			enemy_projectile.position.y = enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_Y_POS]
			enemy_projectile.rotation = enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_ROTATION]
		else:
			call_deferred("_spawn_enemy_projectile", enemy_projectile_dict)
	
	for network_id in client_enemy_projectiles:
		if not current_enemy_projectiles.has(network_id):
			if is_instance_valid(client_enemy_projectiles[network_id]):
				client_enemy_projectiles[network_id].queue_free()
			client_enemy_projectiles.erase(network_id)


func _spawn_enemy_projectile(enemy_projectile_dict : Dictionary) -> void:
	var network_id = enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_NETWORK_ID]
	var enemy_projectile = load(enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_FILENAME]).instance()
	client_enemy_projectiles[network_id] = enemy_projectile
	
	enemy_projectile.position.x = enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_X_POS]
	enemy_projectile.position.y = enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_Y_POS]
	
	enemy_projectile.rotation = enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_ROTATION]
	
	_enemy_projectiles.add_child(enemy_projectile)
	_enemy_projectiles.set_physics_process(false)
	_enemy_projectiles.show()


func _update_batched_hit_particles(batched_hit_effects_array : Array) -> void:
	for hit_effect_dict in batched_hit_effects_array:
		var effect_pos = Vector2(hit_effect_dict["X_POS"], hit_effect_dict["Y_POS"])
		var direction = Vector2(hit_effect_dict["X_DIR"], hit_effect_dict["Y_DIR"])
		var effect_scale = hit_effect_dict["SCALE"]
		_effects_manager.play_hit_effect(effect_pos, direction, effect_scale)


func _update_batched_hit_effects(batched_hit_particles_array : Array) -> void:
	for hit_particles_dict in batched_hit_particles_array:
		var effect_pos = Vector2(hit_particles_dict["X_POS"], hit_particles_dict["Y_POS"])
		var effect_scale = hit_particles_dict["SCALE"]
		_effects_manager.play_hit_particles(effect_pos, Vector2.ZERO, effect_scale)


func _update_batched_floating_text(batched_floating_text_array : Array) -> void:
	for floating_text_dict in batched_floating_text_array:
		var value = floating_text_dict["VALUE"]
		var text_pos = Vector2(floating_text_dict["X_POS"], floating_text_dict["Y_POS"])
		var color = Color8(floating_text_dict["R_COLOR"], floating_text_dict["G_COLOR"], floating_text_dict["B_COLOR"] ,floating_text_dict["A_COLOR"])
		var duration = floating_text_dict["DURATION"]
#		_floating_text_manager.display(value, text_pos, color, null, duration)
		_floating_text_manager.call_deferred("display", value, text_pos, color, null, duration)


func _host_menu_status() -> Dictionary:
	var menu_dict = {}
	
	var showing_upgrade_menus : bool = _coop_upgrades_ui.visible
	menu_dict["MENU_VISIBLE"] = showing_upgrade_menus
	
	if showing_upgrade_menus:
		var player_menus = []
		for player_index in RunData.get_player_count():
			var player_menu_dict = {}
#			_coop_upgrades_ui
			var player_container = _coop_upgrades_ui._get_player_container(player_index)
			
			var showing_player_items_container = player_container._items_container.visible
			var showing_player_upgrades_container = player_container._upgrades_container.visible
			player_menu_dict["SHOWING_ITEMS"] = showing_player_items_container
			player_menu_dict["SHOWING_UPGRADES"] = showing_player_upgrades_container
			player_menu_dict["PLAYER_FINISHED"] = player_container._checkmark_group.visible
			
			if showing_player_upgrades_container:
				var upgrade_options = []
				for upgrade in player_container._old_upgrades:
					var upgrade_data = {}
					upgrade_data["UPGRADE_ID"] = upgrade.my_id
					upgrade_options.push_back(upgrade_data)
				player_menu_dict["UPGRADE_OPTIONS"] = upgrade_options
				player_menu_dict["REROLL_PRICE"] = player_container._reroll_price
			elif showing_player_items_container:
				player_menu_dict["ITEM_ID"] = player_container._item_data.my_id
			
			player_menu_dict["FOCUS"] = _string_for_menu_focus(player_container)
			player_menus.push_back(player_menu_dict)
		menu_dict["PLAYER_MENUS"] = player_menus
	
#	print_debug("Menu DICT: ", menu_dict)
	return menu_dict


func _update_menu(menu_dict : Dictionary) -> void:
	var showing_upgrade_menus : bool = menu_dict["MENU_VISIBLE"]
	
	if showing_upgrade_menus and not _coop_upgrades_ui.visible:
		_coop_upgrades_ui.show()
	elif not showing_upgrade_menus:
		if _coop_upgrades_ui.visible:
			_coop_upgrades_ui.hide()
		return
	
	var player_menus = menu_dict["PLAYER_MENUS"]
	for player_index in RunData.get_player_count():
		var player_container = _coop_upgrades_ui._get_player_container(player_index)
		var player_menu_dict = player_menus[player_index]
		
		var showing_player_items_container = player_menu_dict["SHOWING_ITEMS"]
		var showing_player_upgrades_container = player_menu_dict["SHOWING_UPGRADES"]
		var player_finished = player_menu_dict["PLAYER_FINISHED"]
		if showing_player_upgrades_container:
			var upgrade_options : Array = player_menu_dict["UPGRADE_OPTIONS"]
			var should_update_upgrades : bool = false
			for i in upgrade_options.size():
				if i >= player_container._old_upgrades.size():
					should_update_upgrades = true
				else:
					var upgrade_data = upgrade_options[i]
					if upgrade_data["UPGRADE_ID"] != player_container._old_upgrades[i].my_id:
						should_update_upgrades = true
			if should_update_upgrades:
				var upgrades = []
				for i in upgrade_options.size():
					var upgrade_data = upgrade_options[i]
					for dupe_candidate in ItemService.upgrades:
						if dupe_candidate.my_id == upgrade_data["UPGRADE_ID"]:
							upgrades.push_back(dupe_candidate.duplicate())
				player_container._old_upgrades = upgrades
				var upgrade_uis = player_container._get_upgrade_uis()
				for i in upgrade_options.size():
					var upgrade_ui = upgrade_uis[i]
					upgrade_ui.visible = i < upgrades.size()
					if upgrade_ui.visible:
						upgrade_ui.set_upgrade(upgrades[i], player_index)
				var reroll_price = player_menu_dict["REROLL_PRICE"]
				player_container._reroll_button.init(reroll_price, player_index)
				player_container._update_gold_label()
				
				player_container._items_container.hide()
				player_container._upgrades_container.show()
				player_container.focus()
				
			player_container._items_container.hide()
			player_container._upgrades_container.show()
		elif showing_player_items_container:
			var item_id = player_menu_dict["ITEM_ID"]
			
			if player_container._item_data == null or item_id != player_container._item_data.my_id:
				var item_data
				for item_candidate in ItemService.items:
					if item_id == item_candidate.my_id:
						item_data = item_candidate.duplicate()
						break
				for item_candidate in ItemService.weapons:
					if item_id == item_candidate.my_id:
						item_data = item_candidate.duplicate()
						break
				player_container.show_item(item_data)
				player_container.focus()
			
			player_container._items_container.show()
			player_container._upgrades_container.hide()
		if player_index != my_player_index:
			_focus_for_string(player_container, player_menu_dict["FOCUS"])
		if player_finished:
			player_container._items_container.hide()
			player_container._upgrades_container.hide()
			player_container._checkmark_group.show()


func _update_client_focus(data : Dictionary, player_index : int) -> void:
	if steam_connection.is_host() and player_index != my_player_index:
		var player_container = _coop_upgrades_ui._get_player_container(player_index)
		_focus_for_string(player_container, data["FOCUS"])


func _string_for_menu_focus(player_container : CoopUpgradesUIPlayerContainer) -> String:
	var focus_emulator = player_container.focus_emulator
	if not focus_emulator.focused_control:
		return ""
	
	var focused_control = focus_emulator.focused_control
	if focused_control == player_container._take_button:
		return "take"
	elif focused_control == player_container._discard_button:
		return "discard"
	elif focused_control == player_container._upgrade_ui_1.button:
		return "upgrade_1"
	elif focused_control == player_container._upgrade_ui_2.button:
		return "upgrade_2"
	elif focused_control == player_container._upgrade_ui_3.button:
		return "upgrade_3"
	elif focused_control == player_container._upgrade_ui_4.button:
		return "upgrade_4"
	elif focused_control == player_container._reroll_button:
		return "reroll"
	
	return ""


func _focus_for_string(player_container : CoopUpgradesUIPlayerContainer, focus_key: String) -> void:
	var requested_focused_control = null
	
	if focus_key == "take":
		requested_focused_control = player_container._take_button
	elif focus_key == "discard":
		requested_focused_control = player_container._discard_button
	elif focus_key == "upgrade_1":
		requested_focused_control = player_container._upgrade_ui_1.button
	elif focus_key == "upgrade_2":
		requested_focused_control = player_container._upgrade_ui_2.button
	elif focus_key == "upgrade_3":
		requested_focused_control = player_container._upgrade_ui_3.button
	elif focus_key == "upgrade_4":
		requested_focused_control = player_container._upgrade_ui_4.button
	elif focus_key == "reroll":
		requested_focused_control = player_container._reroll_button
	
	if requested_focused_control:
		player_container.focus_emulator.focused_control = requested_focused_control


func _client_reroll_button_pressed(player_index : int) -> void:
	var player_container = _coop_upgrades_ui._get_player_container(player_index)
	player_container._on_RerollButton_pressed()


func _client_choose_upgrade_button_pressed(upgrade_dict : Dictionary, player_index : int) -> void:
	var player_container = _coop_upgrades_ui._get_player_container(player_index)
	for upgrade_candidate in ItemService.upgrades:
		if upgrade_candidate.my_id == upgrade_dict["UPGRADE_ID"]:
			player_container._on_choose_button_pressed(upgrade_candidate.duplicate())


func _client_take_button_pressed(player_index : int) -> void:
	var player_container = _coop_upgrades_ui._get_player_container(player_index)
	player_container._on_TakeButton_pressed()


func _client_discard_button_pressed(player_index : int) -> void:
	var player_container = _coop_upgrades_ui._get_player_container(player_index)
	player_container._on_DiscardButton_pressed()


func _host_entered_shop() -> void:
	_change_scene(RunData.get_shop_scene_path())


func _check_for_pause() -> void:
	if not in_multiplayer_game:
		._check_for_pause()
