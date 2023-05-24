extends Node
class_name BrotatogetherLobby

var self_peer_id = 0

var id_count = 0

var client_enemies = {}
var client_births = {}
var client_players = {}
var client_items = {}
var client_player_projectiles = {}
var client_consumables = {}
var client_neutrals = {}

var tracked_players = {}

const player_scene = preload("res://entities/units/player/player.tscn")
const entity_birth_scene = preload("res://entities/birth/entity_birth.tscn")
const gold_scene = preload("res://items/materials/gold.tscn")

# TODO all consumables are going to look like fruit for a bit
const consumable_scene = preload("res://items/consumables/consumable.tscn")
const consumable_texture = preload("res://items/consumables/fruit/fruit.png")

# TODO all neutrals are going to be trees for now
const tree_scene = preload("res://entities/units/neutral/tree.tscn") 

#TODO this is the sussiest of bakas
var weapon_stats_resource = ResourceLoader.load("res://weapons/ranged/pistol/1/pistol_stats.tres")
var enabled = false
var current_scene_name = ""

func _ready():
	print_debug("network signals connecting")
	get_tree().connect("network_peer_connected", self, "_player_connected")
	get_tree().connect("network_peer_disconnected", self, "_player_disconnected")
	get_tree().connect("connected_to_server", self, "_connected_ok")
	get_tree().connect("connection_failed", self, "_connected_fail")
	get_tree().connect("server_disconnected", self, "_server_disconnected")
	print_debug("network signals connected")

func _player_connected(id):
	rpc("register_player")

func _player_disconnected(id):
	pass

func reset_client_items():
	client_enemies = {}
	client_births = {}
	client_players = {}
	client_items = {}
	client_player_projectiles = {}
	client_consumables = {}
	client_neutrals = {}

func _connected_ok():
	print_debug("Connection ooookay")
	var current_scene_name = get_tree().get_current_scene().get_name()
	if current_scene_name == "MultiplayerMenu":
		$"/root/MultiplayerMenu/HBoxContainer/InfoBox/Label".text = "connected"
	self_peer_id = get_tree().get_network_unique_id()

func _server_disconnected():
	pass # Server kicked us; show error and abort.

func _connected_fail():
	print_debug("Connection Failllled")
	pass # Could not even connect to server; abort.

remotesync func register_player():
	var id = get_tree().get_rpc_sender_id()
	print_debug("player registered ", id)
	
	if not client_players.has(id):
		client_players[id] = {}

remote func start_game(game_info: Dictionary):
	print_debug("should be trying to start game")
	tracked_players = {}
	RunData.current_wave = game_info.current_wave
	RunData.add_character(load("res://items/characters/well_rounded/well_rounded_data.tres"))
	get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/extensions/client_main.tscn")
	reset_client_items()
	enabled = true

remote func display_floating_text(text_info:Dictionary):
	if not enabled:
		return
	if $"/root/ClientMain":
		$"/root/ClientMain/FloatingTextManager".display(text_info.value, text_info.position, text_info.color)

remote func display_hit_effect(effect_info: Dictionary):
	if not enabled:
		return
	if $"/root/ClientMain/EffectsManager":
		var effects_manager = $"/root/ClientMain/EffectsManager"
		effects_manager.play_hit_particles(effect_info.position, effect_info.direction, effect_info.scale)
		effects_manager.play_hit_effect(effect_info.position, effect_info.direction, effect_info.scale)

func send_client_position():
	if not tracked_players.has(self_peer_id):
		return
	var my_player = tracked_players[self_peer_id]["player"]
	var client_positions = {}
	client_positions["player"] = my_player.position
	client_positions["movement"] = my_player._current_movement
	var weapons = []
	for weapon in my_player.current_weapons:
		var weapon_data = {}
		weapon_data["weapon_id"] = weapon.weapon_id
		weapon_data["position"] = weapon.sprite.position
		weapon_data["rotation"] = weapon.sprite.rotation
		weapon_data["hitbox_disabled"] = weapon._hitbox._collision.disabled
		weapons.push_back(weapon_data)
	client_positions["weapons"] = weapons
	
	rpc("update_client_position", client_positions)

remote func update_client_position(client_positions:Dictionary):
	if get_tree().is_network_server():
		var id = get_tree().get_rpc_sender_id()
		if tracked_players.has(id):
			if tracked_players[id].has("player"):
				var player = tracked_players[id]["player"]
				player.position = client_positions.player
				player.maybe_update_animation(client_positions.movement, true)
				
				for weapon_data_index in client_positions.weapons.size():
					var weapon_data = client_positions.weapons[weapon_data_index]
					var weapon = player.current_weapons[weapon_data_index]
					var disabled = weapon_data.hitbox_disabled
#					if disabled:
#						weapon.disable_hitbox()
#					else:
#						weapon.enable_hitbox()
					
					weapon.sprite.position = weapon_data.position
					weapon.sprite.rotation = weapon_data.rotation
					
remote func send_shot(shot_data:Dictionary):
	var player_id = get_tree().get_rpc_sender_id()
	var weapon = tracked_players[player_id]["player"].current_weapons[shot_data.weapon_index]
	
	WeaponService.spawn_projectile(shot_data.rotation, 
		weapon.current_stats, 
		weapon.muzzle.global_position, 
		shot_data.knockback, 
		false, 
		weapon.effects, 
		weapon
	)

remote func enemy_death(enemy_id):
	if client_enemies.has(enemy_id):
		if is_instance_valid(client_enemies[enemy_id]):
			client_enemies[enemy_id].die()
			
remote func end_wave():
	enabled = false
	reset_client_items()
	get_tree().change_scene("res://mods-unpacked/pasha-Brotatogether/extensions/waiting.tscn")

remote func update_player_position(data):
	if current_scene_name != "ClientMain":
#		print_debug(currentK)
		return
	if not enabled:
		return
	var server_enemies = {}
	for enemy_data in data.enemies:
		if not client_enemies.has(enemy_data.id):
			if not enemy_data.has("filename"):
				continue
			var enemy = spawn_enemy(enemy_data)
			client_enemies[enemy_data.id] = enemy
		
		var stored_enemy = client_enemies[enemy_data.id]
		if is_instance_valid(stored_enemy):
			server_enemies[enemy_data.id] = true
			stored_enemy.position = enemy_data.position
			stored_enemy.call_deferred("update_animation", enemy_data.movement)
	
	for enemy_id in client_enemies:
		if not server_enemies.has(enemy_id):
			# TODO clean this up when the animation finishes
#			$"/root/ClientMain/Entities".remove_child(client_enemies[enemy_id])
			client_enemies.erase(enemy_id)
			
	# Add and remove births
	var server_births = {}
	for birth_data in data.births:
		if not client_births.has(birth_data.id):
			var birth = spawn_entity_birth(birth_data)
			client_births[birth_data.id] = birth
		server_births[birth_data.id] = true
	for birth_id in client_births:
		if not server_births.has(birth_id):
			var birth_to_delete = client_births[birth_id]
			if birth_to_delete:
#				Children go away on their own when they time out?
#				$"/root/ClientMain/Births".remove_child(birth_to_delete)
				client_births.erase(birth_id) 

	# Add and remove gold
	var server_items = {}
	for item_data in data.items:
		if not client_items.has(item_data.id):
			client_items[item_data.id] = spawn_gold(item_data)
		if is_instance_valid(client_items[item_data.id]):
			client_items[item_data.id].global_position = item_data.position
			# The item will try to float around on its own
			client_items[item_data.id].push_back_destination = item_data.position
		
		server_items[item_data.id] = true
	for item_id in client_items:
		if not server_items.has(item_id):
			var item = client_items[item_id]
			if not client_items[item_id]:
				continue
			
			client_items.erase(item_id)
			if not $"/root/ClientMain/Items":
				continue 
			if not item:
				continue
			# This sometimes throws a C++ error
			$"/root/ClientMain/Items".remove_child(item)
			
	var server_player_projectiles = {}
	for player_projectile_data in data.projectiles:
		var projectile_id = player_projectile_data.id
		if not client_player_projectiles.has(projectile_id):
			client_player_projectiles[projectile_id] = spawn_player_projectile(player_projectile_data)
		
		var player_projectile = client_player_projectiles[projectile_id]
		if is_instance_valid(player_projectile):
			player_projectile.position = player_projectile_data.position
			player_projectile.rotation = player_projectile_data.rotation
		server_player_projectiles[projectile_id] = true
		
	for projectile_id in client_player_projectiles:
		if not server_player_projectiles.has(projectile_id):
			var player_projectile = client_player_projectiles[projectile_id]
			client_player_projectiles.erase(projectile_id)
			if is_instance_valid(player_projectile):
				get_tree().current_scene.remove_child(player_projectile)
				
	var server_consumables = {}
	for server_consumable_data in data.consumables:
		var consumable_id = server_consumable_data.id
		if not client_consumables.has(consumable_id):
			client_consumables[consumable_id] = spawn_consumable(server_consumable_data)
			
		var consumable = client_consumables[consumable_id]
		if is_instance_valid(consumable):
			consumable.global_position = server_consumable_data.position
		server_consumables[consumable_id] = true
	
	for consumable_id in client_consumables:
		if not server_consumables.has(consumable_id):
			var consumable = client_consumables[consumable_id]
			client_consumables.erase(consumable_id)
			if is_instance_valid(consumable):
				$"/root/ClientMain/Consumables".remove_child(consumable)
				
	var server_neutrals = {}
	for server_neutral_data in data.neutrals:
		var neutral_id = server_neutral_data.id
		if not client_neutrals.has(neutral_id):
			client_neutrals[neutral_id] = spawn_neutral(server_neutral_data)
		var neutral = client_neutrals[neutral_id]
		if is_instance_valid(neutral):
			neutral.global_position = server_neutral_data.position
		server_neutrals[neutral_id] = true
	for neutral_id in client_neutrals:
		if not server_neutrals.has(neutral_id):
			var neutral = client_neutrals[neutral_id]
			client_neutrals.erase(neutral_id)
			if is_instance_valid(neutral):
				$"/root/ClientMain/Entities".remove_child(neutral)
		
	for player_data in data.players:
		var player_id = player_data.id
		if not player_id in tracked_players:
			print_debug("spawning player for ", player_id)
			tracked_players[player_id] = {}
			tracked_players[player_id]["player"] = spawn_player(player_data)
			
		var player = tracked_players[player_id]["player"]
		if player_id == self_peer_id:
			if $"/root/ClientMain":
				var main = $"/root/ClientMain"
				main._life_bar.update_value(player_data.current_health, player_data.max_health)
				main.set_life_label(player_data.current_health, player_data.max_health)
				main._damage_vignette.update_from_hp(player_data.current_health, player_data.max_health)
		else:
			if is_instance_valid(player):
				player.position = player_data.position
				player.call_deferred("maybe_update_animation", player_data.movement, true)
			
		for weapon_data_index in player.current_weapons.size():
			var weapon_data = player_data.weapons[weapon_data_index]
			var weapon = player.current_weapons[weapon_data_index]
			weapon.sprite.position = weapon_data.position
			weapon.sprite.rotation = weapon_data.rotation
			weapon._is_shooting = weapon_data.shooting

func spawn_enemy(enemy_data: Dictionary):
	var entity = load(enemy_data.filename).instance()
	
	entity.position = enemy_data.position
	entity.stats = load(enemy_data.resource)
	
	_clear_movement_behavior(entity)
	
	$"/root/ClientMain/Entities".add_child(entity)
	
	return entity

func spawn_player(player_data:Dictionary):
	var spawned_player = player_scene.instance()
	spawned_player.position = player_data.position
	spawned_player.current_stats.speed = player_data.speed
	
	for weapon in player_data.weapons:
		print_debug("spawning player with weapon ", weapon.data_path)
		spawned_player.call_deferred("add_weapon", load(weapon.data_path), spawned_player.current_weapons.size())
	
	$"/root/ClientMain/Entities".add_child(spawned_player)
	
	if player_data.id == self_peer_id:
		spawned_player.get_remote_transform().remote_path = $"/root/ClientMain/Camera".get_path()
	spawned_player.call_deferred("remove_weapon_behaviors")
	
	return spawned_player

func spawn_entity_birth(entity_birth_data:Dictionary):
	var entity_birth = entity_birth_scene.instance()
	
	entity_birth.color = entity_birth_data.color
	entity_birth.global_position = entity_birth_data.position
	
	$"/root/ClientMain/Entities".add_child(entity_birth)
	
	return entity_birth

func spawn_gold(item_data:Dictionary):
	var gold = gold_scene.instance()
	
	gold.global_position = item_data.position
	gold.scale.x = item_data.scale_x
	gold.scale.y = item_data.scale_y
	gold.rotation = item_data.rotation
	gold.push_back_destination = item_data.push_back_destination
	
	$"/root/ClientMain/Items".add_child(gold)
	
	return gold

func spawn_player_projectile(projectile_data:Dictionary):
	var main = $"/root/ClientMain"
	var projectile = load(projectile_data.filename).instance()
	
	projectile.position = projectile_data.position
	projectile.spawn_position = projectile_data.global_position
	projectile.global_position = projectile_data.global_position
	projectile.rotation = projectile_data.rotation
	projectile.weapon_stats = weapon_stats_resource.duplicate()
	projectile.set_physics_process(false)
	
	main.add_child(projectile, true)
	
	projectile.call_deferred("set_physics_process", false)
	
	return projectile

func spawn_consumable(consumable_data:Dictionary):
	var consumable = consumable_scene.instance()
	
	consumable.global_position = consumable_data.position
	consumable.call_deferred("set_texture", consumable_texture)
	consumable.call_deferred("set_physics_process", false)
	
	$"/root/ClientMain/Consumables".add_child(consumable)
	
	return consumable

func spawn_neutral(neutral_data:Dictionary):
	var neutral = tree_scene.instance()
	neutral.global_position = neutral_data.position
	
	$"/root/ClientMain/Entities".add_child(neutral)
	
	return neutral

func _process(delta):
	if not get_tree().has_network_peer():
		return
	var scene_name = get_tree().get_current_scene().get_name()
	if get_tree().is_network_server():
		# TODO i can't seem to override Shop.gd because it errors trying to get
		# a RunData field, we'll do this gargbage instead.
		scene_name = get_tree().get_current_scene().get_name()
		if scene_name != current_scene_name:
			if current_scene_name == "Shop":
				# First frame where we left the shop
				var rpc_data = {"current_wave":RunData.current_wave}
				rpc("start_game", rpc_data)
	current_scene_name = scene_name


# TODO: DEDUPE
func _clear_movement_behavior(entity:Entity, is_player:bool = false) -> void:
	# Players will only move via client calls, locally make them do
	# nothing
	# Since the player is added before it's children can be manipulatd,
	# manually set the current movement behavior to set it correctly
	var movement_behavior = entity.get_node("MovementBehavior")
	entity.remove_child(movement_behavior)
	var client_movement_behavior = ClientMovementBehavior.new()
	client_movement_behavior.set_name("MovementBehavior")
	entity.add_child(client_movement_behavior, true)
	entity._current_movement_behavior = client_movement_behavior
	
	if not is_player:
		var attack_behavior = entity.get_node("AttackBehavior")
		entity.remove_child(attack_behavior)
		var client_attack_behavior = ClientAttackBehavior.new()
		client_attack_behavior.set_name("AttackBehavior")
		entity.add_child(client_attack_behavior, true)
		entity._current_attack_behavior = client_attack_behavior
	
	if is_player:
		entity.call_deferred("remove_weapon_behaviors")
