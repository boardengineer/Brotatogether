extends Node

# here they'll be keyed by steam user ids
var tracked_players = {}
var connection

var client_enemies = {}
var client_births = {}
var client_players = {}
var client_items = {}
var client_player_projectiles = {}
var client_consumables = {}
var client_neutrals = {}

var self_peer_id
var is_host
var id_count = 0

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

var current_scene_name = ""
var run_updates = false

func _process(delta):
	var scene_name = get_tree().get_current_scene().get_name()
	if is_host:
		# TODO i can't seem to override Shop.gd because it errors trying to get
		# a RunData field, we'll do this gargbage instead.
		scene_name = get_tree().get_current_scene().get_name()
		if scene_name != current_scene_name:
			if current_scene_name == "Shop":
				# First frame where we left the shop
				var wave_data = {"current_wave":RunData.current_wave}
				send_start_game(wave_data)
	current_scene_name = scene_name

func start_game(game_info: Dictionary):
	tracked_players = {}
	RunData.current_wave = game_info.current_wave
	RunData.add_character(load("res://items/characters/well_rounded/well_rounded_data.tres"))
	get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/extensions/client_main.tscn")
	reset_client_items()
	run_updates = true
#	enabled = true

func display_floating_text(text_info:Dictionary):
	if $"/root/ClientMain":
		$"/root/ClientMain/FloatingTextManager".display(text_info.value, text_info.position, text_info.color)

func display_hit_effect(effect_info: Dictionary):
	if $"/root/ClientMain/EffectsManager":
		var effects_manager = $"/root/ClientMain/EffectsManager"
		effects_manager.play_hit_particles(effect_info.position, effect_info.direction, effect_info.scale)
		effects_manager.play_hit_effect(effect_info.position, effect_info.direction, effect_info.scale)

func enemy_death(enemy_id):
	if client_enemies.has(enemy_id):
		if is_instance_valid(client_enemies[enemy_id]):
			client_enemies[enemy_id].die()

func end_wave():
	run_updates = false
	reset_client_items()
	get_tree().change_scene("res://mods-unpacked/pasha-Brotatogether/extensions/waiting.tscn")

func flash_enemy(enemy_id):
	if client_enemies.has(enemy_id):
		if is_instance_valid(client_enemies[enemy_id]):
			client_enemies[enemy_id].flash()

func flash_neutral(neutral_id):
	if client_neutrals.has(neutral_id):
		if is_instance_valid(client_neutrals[neutral_id]):
			client_neutrals[neutral_id].flash()

func send_game_state() -> void:
	connection.send_state(get_game_state())

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

func update_game_state(data):
	if not run_updates or current_scene_name != "ClientMain":
		return
	update_enemies(data.enemies)
	update_births(data.births)
	update_items(data.items)
	update_player_projectiles(data.projectiles)
	update_consumables(data.consumables)
	update_neutrals(data.neutrals)
	update_players(data.players)

func get_game_state() -> Dictionary:
	var main = $"/root/Main"
	var data = {}
	var position = main._player.position
	var entity_spawner = main._entity_spawner

	data["enemies"] = get_enemies_state()
	data["births"] = get_births_state()
	data["items"] = get_items_state()
	data["players"] = get_players_state()
	data["projectiles"] = get_projectiles_state()
	data["consumables"] = get_consumables_state()
	data["neutrals"] = get_neutrals_state()

	return data
	
func send_client_position() -> void:
	print_debug("self id ", self_peer_id)
	if not tracked_players.has(self_peer_id):
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
	if is_host:
		var id = client_position.id
		if tracked_players.has(id):
			if tracked_players[id].has("player"):
				var player = tracked_players[id]["player"]
				player.position = client_position.player
				player.maybe_update_animation(client_position.movement, true)

func get_enemies_state() -> Dictionary:
	var main = $"/root/Main"
	var enemies = []
	var entity_spawner = main._entity_spawner
	for enemy in entity_spawner.enemies:
		if is_instance_valid(enemy):
				var network_id = enemy.id
				var enemy_data = {}
				enemy_data["id"] = network_id

				# TODO Details only needed on spawn, send sparingly
				enemy_data["resource"] = enemy.stats.resource_path
				enemy_data["filename"] = enemy.filename

				enemy_data["position"] = enemy.position
				enemy_data["movement"] = enemy._current_movement

				enemies.push_back(enemy_data)
	return enemies

func update_enemies(enemies:Array) -> void:
	var server_enemies = {}
	for enemy_data in enemies:
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

func get_births_state() -> Dictionary:
	var main = $"/root/Main"
	var births = []
	for birth in main._entity_spawner.births:
		if is_instance_valid(birth):
			var birth_data = {}
			birth_data["position"] = birth.global_position
			birth_data["color"] = birth.color
			birth_data["id"] = birth.id
			births.push_back(birth_data)
	return births

func update_births(births:Array) -> void:
	var server_births = {}
	for birth_data in births:
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

func update_items(items:Array) -> void:
	var server_items = {}
	for item_data in items:
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

func get_players_state() -> Dictionary:
	var players = []
	for player_id in tracked_players:
		var player_data = {}
		var tracked_player = tracked_players[player_id]["player"]
		player_data["id"] = player_id
		player_data["position"] = tracked_player.position
		player_data["speed"] = tracked_player.current_stats.speed
		player_data["movement"] = tracked_player._current_movement
		player_data["current_health"] = tracked_player.current_stats.health
		player_data["max_health"] = tracked_player.max_stats.health

		# This would be where individual inventories are sent out instead of
		# RunData.gold
		player_data["gold"] = RunData.gold

		var weapons = []
		for weapon in tracked_player.current_weapons:
			var weapon_data = {}
			weapon_data["weapon_id"] = weapon.weapon_id
			weapon_data["position"] = weapon.sprite.position
			weapon_data["rotation"] = weapon.sprite.rotation
			weapon_data["shooting"] = weapon._is_shooting

			if weapon.has_node("data_node"):
				var weapon_data_path = RunData.weapon_paths[weapon.get_node("data_node").weapon_data.my_id]
				weapon_data["data_path"] = weapon_data_path
#				print_debug("data_node ", data_resource_path)

			weapons.push_back(weapon_data)

		player_data["weapons"] = weapons
		players.push_back(player_data)
	return players

func update_players(players:Array) -> void:
	for player_data in players:
		var player_id = player_data.id
		if not player_id in tracked_players:
			print_debug("spawned player ", player_id)
			tracked_players[player_id] = {}
			tracked_players[player_id]["player"] = spawn_player(player_data)

		var player = tracked_players[player_id]["player"]
		if player_id == self_peer_id:
			if $"/root/ClientMain":
				var main = $"/root/ClientMain"
				main._life_bar.update_value(player_data.current_health, player_data.max_health)
				main.set_life_label(player_data.current_health, player_data.max_health)
				main._damage_vignette.update_from_hp(player_data.current_health, player_data.max_health)
				print_debug("received gold ", player_data.gold)
				RunData.gold = player_data.gold
				$"/root/ClientMain"._ui_gold.on_gold_changed(player_data.gold)
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

func update_player_projectiles(projectiles:Array) -> void:
	var server_player_projectiles = {}
	for player_projectile_data in projectiles:
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

func get_consumables_state() -> Dictionary:
	var main = $"/root/Main"
	var consumables = []
	for consumable in main._consumables_container.get_children():
		var consumable_data = {}
		consumable_data["position"] = consumable.global_position
		consumable_data["id"] = consumable.id
		consumables.push_back(consumable_data)
	return consumables

func update_consumables(consumables:Array) -> void:
	var server_consumables = {}
	for server_consumable_data in consumables:
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

func get_neutrals_state() -> Dictionary:
	var main = $"/root/Main"
	var neutrals = []
	for neutral in main._entity_spawner.neutrals:
		if is_instance_valid(neutral):
			var neutral_data = {}
			neutral_data["id"] = neutral.id
			neutral_data["position"] = neutral.global_position
			neutrals.push_back(neutral_data)
	return neutrals

func update_neutrals(neutrals:Array) -> void:
	var server_neutrals = {}
	for server_neutral_data in neutrals:
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
		spawned_player.call_deferred("add_weapon", load(weapon.data_path), spawned_player.current_weapons.size())

	print_debug("current scene ", get_tree().get_current_scene().get_name())
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

func reset_client_items():
	client_enemies = {}
	client_births = {}
	client_players = {}
	client_items = {}
	client_player_projectiles = {}
	client_consumables = {}
	client_neutrals = {}
	
	tracked_players = {}
