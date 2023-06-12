extends Node

var client_enemies = {}
var client_births = {}
var client_players = {}
var client_items = {}
var client_player_projectiles = {}
var client_consumables = {}
var client_neutrals = {}

var parent
var run_updates = false

const gold_scene = preload("res://items/materials/gold.tscn")
const entity_birth_scene = preload("res://entities/birth/entity_birth.tscn")
const consumable_scene = preload("res://items/consumables/consumable.tscn")
const consumable_texture = preload("res://items/consumables/fruit/fruit.png")
const player_scene = preload("res://entities/units/player/player.tscn")

#TODO this is the sussiest of bakas
var weapon_stats_resource = ResourceLoader.load("res://weapons/ranged/pistol/1/pistol_stats.tres")

# TODO all neutrals are going to be trees for now
const tree_scene = preload("res://entities/units/neutral/tree.tscn")

const ClientMovementBehavior = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/entities/units/enemies/client_movement_behavior.gd")
const ClientAttackBehavior = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/entities/units/enemies/client_attack_behavior.gd")

const ID_INDEX = 0

const ENEMY_POSITION_X_INDEX = 1
const ENEMY_POSITION_Y_INDEX = 2
const ENEMY_MOVEMENT_X_INDEX = 3
const ENEMY_MOVEMENT_Y_INDEX = 4
const ENEMY_RESOURCE_INDEX = 5
const ENEMY_FILENAME_INDEX = 6

const ITEM_SCALE_X_INDEX = 1
const ITEM_SCALE_Y_INDEX = 2
const ITEM_POSITION_INDEX = 3
const ITEM_ROTATION_INDEX = 4
const ITEM_PUSH_BACK_DESTINATION_INDEX = 5

const PLAYER_POSITION_INDEX = 1
const PLAYER_SPEED_INDEX = 2
const PLAYER_MOVEMENT_INDEX = 3
const PLAYER_CURRENT_HEALTH_INDEX = 4
const PLAYER_MAX_HEALTH_INDEX = 5
const PLAYER_GOLD_INDEX = 6
const PLAYER_WEAPONS_INDEX = 7

const WEAPON_POSITION_INDEX = 1
const WEAPON_ROTATION_INDEX = 2
const WEAPON_SHOOTING_INDEX = 3
const WEAPON_DATA_PATH_INDEX = 4

# TODO sometimes clear these
var sent_detail_ids = {}

func get_items_state() -> PoolByteArray:
	var buffer = StreamPeerBuffer.new()
	var main = $"/root/Main"
	
	var num_items = main._items_container.get_children().size()
	buffer.put_u16(num_items)
	
	for item in main._items_container.get_children():
		buffer.put_32(item.id)
		buffer.put_float(item.global_position.x)
		buffer.put_float(item.global_position.y)
				
		if not sent_detail_ids.has(item.id):
			buffer.put_8(1)
			
			buffer.put_float(item.scale.x)
			buffer.put_float(item.scale.y)
			
			buffer.put_float(item.rotation)
			
			buffer.put_float(item.push_back_destination.x)
			buffer.put_float(item.push_back_destination.y)
			
			sent_detail_ids[item.id] = true
		else:
			buffer.put_8(0)

		# TODO we may want textures propagated
	return buffer.data_array

func update_items(items:PoolByteArray) -> void:
	var server_items = {}
	
	var buffer = StreamPeerBuffer.new()
	buffer.data_array = items
	
	var num_items = buffer.get_u16()
	
	for _item_index in num_items:
		var item_id = buffer.get_32()
		
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		
		var has_detail = buffer.get_8() == 1
		
		var scale_x = 0.0
		var scale_y = 0.0
		
		var rotation = 0.0
		
		var push_back_x = 0.0
		var push_back_y = 0.0
		
		if has_detail:
			scale_x = buffer.get_float()
			scale_y = buffer.get_float()
			rotation = buffer.get_float()
			push_back_x = buffer.get_float()
			push_back_y = buffer.get_float()
			
		if not client_items.has(item_id):
			client_items[item_id] = spawn_gold(Vector2(pos_x, pos_y), Vector2(scale_x, scale_y), rotation, Vector2(push_back_x, push_back_y))
		if is_instance_valid(client_items[item_id]):
			client_items[item_id].global_position = Vector2(pos_x, pos_y)
			client_items[item_id].push_back_destination = Vector2(pos_x, pos_y)

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

func spawn_gold(position:Vector2, scale:Vector2, rotation:float, push_back_destination: Vector2):
	var gold = gold_scene.instance()
	
	gold.global_position = position
	gold.scale = scale
	gold.rotation = rotation
	gold.push_back_destination = push_back_destination
	
	$"/root/ClientMain/Items".add_child(gold)
	
	return gold

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

func spawn_player_projectile(projectile_data:Dictionary):
	var main = $"/root/ClientMain"
	var projectile = load(projectile_data.filename).instance()
	
	projectile.position = projectile_data.position
	projectile.spawn_position = projectile_data.global_position
	projectile.global_position = projectile_data.global_position
	projectile.rotation = projectile_data.rotation
	# TODO this is probably wrong?
	projectile.weapon_stats = weapon_stats_resource.duplicate()
	projectile.set_physics_process(false)
	
	main.add_child(projectile, true)
	
	projectile.call_deferred("set_physics_process", false)
	
	return projectile

func enemy_death(enemy_id):
	if client_enemies.has(enemy_id):
		if is_instance_valid(client_enemies[enemy_id]):
			client_enemies[enemy_id].die()

func flash_enemy(enemy_id):
	if client_enemies.has(enemy_id):
		if is_instance_valid(client_enemies[enemy_id]):
			client_enemies[enemy_id].flash()

func flash_neutral(neutral_id):
	if client_neutrals.has(neutral_id):
		if is_instance_valid(client_neutrals[neutral_id]):
			client_neutrals[neutral_id].flash()
			
func update_enemies(enemies:PoolByteArray) -> void:
	var server_enemies = {}
	var buffer = StreamPeerBuffer.new()
	buffer.data_array = enemies
	
	var num_enemies = buffer.get_u16()
	
	for _enemy_index in num_enemies:
		var enemy_id = buffer.get_32()
		var has_filenames = buffer.get_8() == 1
		var filename = ""
		var resource_path = ""
		
		if has_filenames:
			resource_path = buffer.get_string()
			
			filename = buffer.get_string()
		
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		var mov_x = buffer.get_float()
		var mov_y = buffer.get_float()
		
		var position = Vector2(pos_x, pos_y)
		var movement = Vector2(mov_x, mov_y)
		
		if not client_enemies.has(enemy_id):
			if not has_filenames:
				continue
			var enemy = spawn_enemy(position, filename, resource_path)
			client_enemies[enemy_id] = enemy
			
		var stored_enemy = client_enemies[enemy_id]
		if is_instance_valid(stored_enemy):
			server_enemies[enemy_id] = true
			stored_enemy.position = position
			stored_enemy.call_deferred("update_animation", movement)


func spawn_enemy(position:Vector2, filename:String, resource_path:String):
	var entity = load(filename).instance()

	entity.position = position
	entity.stats = load(resource_path)

	_clear_movement_behavior(entity)

	$"/root/ClientMain/Entities".add_child(entity)

	return entity


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

func update_game_state(data: Dictionary) -> void:
	if get_tree().get_current_scene().get_name() != "ClientMain":
		return
	update_enemies(data.enemies)
	update_births(data.births)
	update_items(data.items)
	update_player_projectiles(data.projectiles)
	update_consumables(data.consumables)
	update_neutrals(data.neutrals)
	update_players(data.players)

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

func spawn_entity_birth(entity_birth_data:Dictionary):
	var entity_birth = entity_birth_scene.instance()
	
	entity_birth.color = entity_birth_data.color
	entity_birth.global_position = entity_birth_data.position
	
	$"/root/ClientMain/Entities".add_child(entity_birth)
	
	return entity_birth

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

func reset_client_items():
	client_enemies = {}
	client_births = {}
	client_players = {}
	client_items = {}
	client_player_projectiles = {}
	client_consumables = {}
	client_neutrals = {}

func update_players(players:Array) -> void:
	var tracked_players = parent.tracked_players
	for player_data in players:
		var player_id = player_data[ID_INDEX]
		if not player_id in tracked_players:
			tracked_players[player_id] = {}
		
		if not tracked_players[player_id].has("player") or not is_instance_valid(tracked_players[player_id].player):
			tracked_players[player_id]["player"] = spawn_player(player_data)

		var player = tracked_players[player_id]["player"]
		if player_id == parent.self_peer_id:
			if $"/root/ClientMain":
				var main = $"/root/ClientMain"
				main._life_bar.update_value(player_data[PLAYER_CURRENT_HEALTH_INDEX], player_data[PLAYER_MAX_HEALTH_INDEX])
				main.set_life_label(player_data[PLAYER_CURRENT_HEALTH_INDEX], player_data[PLAYER_MAX_HEALTH_INDEX])
				main._damage_vignette.update_from_hp(player_data[PLAYER_CURRENT_HEALTH_INDEX], player_data[PLAYER_MAX_HEALTH_INDEX])
				RunData.gold = player_data[PLAYER_GOLD_INDEX]
				$"/root/ClientMain"._ui_gold.on_gold_changed(player_data[PLAYER_GOLD_INDEX])
		else:
			if is_instance_valid(player):
				player.position = player_data[PLAYER_POSITION_INDEX]
				player.call_deferred("maybe_update_animation", player_data[PLAYER_MOVEMENT_INDEX], true)

		if is_instance_valid(player):
			for weapon_data_index in player.current_weapons.size():
				var weapon_data = player_data[PLAYER_WEAPONS_INDEX][weapon_data_index]
				var weapon = player.current_weapons[weapon_data_index]
				weapon.sprite.position = weapon_data[WEAPON_POSITION_INDEX]
				weapon.sprite.rotation = weapon_data[WEAPON_ROTATION_INDEX]
				weapon._is_shooting = weapon_data[WEAPON_SHOOTING_INDEX]

func spawn_player(player_data:Dictionary):
	var spawned_player = player_scene.instance()
	spawned_player.position = player_data[PLAYER_POSITION_INDEX]
	spawned_player.current_stats.speed = player_data[PLAYER_SPEED_INDEX]

	for weapon in player_data[PLAYER_WEAPONS_INDEX]:
		spawned_player.call_deferred("add_weapon", load(weapon[WEAPON_DATA_PATH_INDEX]), spawned_player.current_weapons.size())

	$"/root/ClientMain/Entities".add_child(spawned_player)

	if player_data[ID_INDEX] == parent.self_peer_id:
		spawned_player.get_remote_transform().remote_path = $"/root/ClientMain/Camera".get_path()
	spawned_player.call_deferred("remove_weapon_behaviors")

	return spawned_player

func get_game_state() -> Dictionary:
	var data = {}
		
	if "/root/Main":
		var main = $"/root/Main"
		if main:
			data["enemies"] = get_enemies_state()
			data["births"] = get_births_state()
			data["items"] = get_items_state()
			data["players"] = get_players_state()
			data["projectiles"] = get_projectiles_state()
			data["consumables"] = get_consumables_state()
			data["neutrals"] = get_neutrals_state()
			
#	print_debug("size: ", var2bytes(data).size(), " ", str(data.enemies).length(), " ", str(data.births).length(), " ", str(data.items).length(), " ", str(data.players).length(), " ", str(data.projectiles).length(), " ", str(data.consumables).length(), " ", str(data.neutrals).length())
#	print_debug("size 2: ", data.enemies.size())
#	print_debug("size 2.5: ", (str(data.enemies)).length())
#	print_debug("size 3: ", var2bytes(data.enemies).size())
#	print_debug("size 4: ", data.enemies.compress(File.COMPRESSION_GZIP).size())
	
	print_debug(data.players)


	return data

func get_enemies_state() -> PoolByteArray:
	var buffer = StreamPeerBuffer.new()
	var main = $"/root/Main"
	var enemies = []
	var entity_spawner = main._entity_spawner
	
	var num_enemies = entity_spawner.enemies.size()
	buffer.put_u16(num_enemies)
	
	for enemy in entity_spawner.enemies:
		if is_instance_valid(enemy):
				var network_id = enemy.id
				buffer.put_32(network_id)

				if not sent_detail_ids.has(network_id):
					buffer.put_8(1)
					
					buffer.put_string(enemy.stats.resource_path)
					buffer.put_string(enemy.filename)
					
					sent_detail_ids[network_id] = true
				else:
					buffer.put_8(0)
				
				buffer.put_float(enemy.position.x)
				buffer.put_float(enemy.position.y)
				buffer.put_float(enemy._current_movement.x)
				buffer.put_float(enemy._current_movement.y)
	return buffer.data_array

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

func get_players_state() -> Dictionary:
	var tracked_players = parent.tracked_players
	var players = []
	for player_id in tracked_players:
		var player_data = {}
		var tracked_player = tracked_players[player_id]["player"]
		player_data[ID_INDEX] = player_id
		player_data[PLAYER_POSITION_INDEX] = tracked_player.position
		player_data[PLAYER_SPEED_INDEX] = tracked_player.current_stats.speed
		player_data[PLAYER_MOVEMENT_INDEX] = tracked_player._current_movement
		player_data[PLAYER_CURRENT_HEALTH_INDEX] = tracked_player.current_stats.health
		player_data[PLAYER_MAX_HEALTH_INDEX] = tracked_player.max_stats.health

		# This would be where individual inventories are sent out instead of
		# RunData.gold
		player_data[PLAYER_GOLD_INDEX] = RunData.gold

		var weapons = []
		for weapon in tracked_player.current_weapons:
			if not is_instance_valid(weapon):
				continue
			var weapon_data = {}
			weapon_data[WEAPON_POSITION_INDEX] = weapon.sprite.position
			weapon_data[WEAPON_ROTATION_INDEX] = weapon.sprite.rotation
			weapon_data[WEAPON_SHOOTING_INDEX] = weapon._is_shooting

			if not sent_detail_ids.has(player_id):
				if weapon.has_node("data_node"):
					var weapon_data_path = RunData.weapon_paths[weapon.get_node("data_node").weapon_data.my_id]
					weapon_data[WEAPON_DATA_PATH_INDEX] = weapon_data_path
#				TODO: uncomment this to stop writes, it'll cause problems later though
#				sent_detail_ids[player_id] = true

			weapons.push_back(weapon_data)

		player_data[PLAYER_WEAPONS_INDEX] = weapons
		players.push_back(player_data)
	return players

func get_consumables_state() -> Dictionary:
	var main = $"/root/Main"
	var consumables = []
	for consumable in main._consumables_container.get_children():
		var consumable_data = {}
		consumable_data["position"] = consumable.global_position
		consumable_data["id"] = consumable.id
		consumables.push_back(consumable_data)
	return consumables

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
