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

# TODO sometimes clear these
var sent_detail_ids = {}

func get_game_state() -> PoolByteArray:
	var buffer = StreamPeerBuffer.new()
		
	if "/root/Main":
		var main = $"/root/Main"
		if main:
			get_players_state(buffer)
			get_enemies_state(buffer)
			get_births_state(buffer)
			get_items_state(buffer)
			get_projectiles_state(buffer)
			get_consumables_state(buffer)
			get_neutrals_state(buffer)
		
#	print_debug("enemies type ", typeof(get_enemies_state()))
#	print_debug("births type ", typeof(get_births_state()))
#	print_debug("items type ", typeof(get_items_state()))
#	print_debug("players type ", typeof(get_players_state()))
#	print_debug("projectiles type ", typeof(get_projectiles_state()))
#	print_debug("consumables type ", typeof(get_consumables_state()))
#	print_debug("neutrals type ", typeof(get_neutrals_state()))
	
	return buffer.data_array

func update_game_state(data: PoolByteArray) -> void:
	if get_tree().get_current_scene().get_name() != "ClientMain":
		return
		
	var buffer = StreamPeerBuffer.new()
	buffer.data_array = data
	
	update_players(buffer)
	update_enemies(buffer)
	update_births(buffer)
	update_items(buffer)
	update_player_projectiles(buffer)
	update_consumables(buffer)
	update_neutrals(buffer)

func get_items_state(buffer: StreamPeerBuffer) -> PoolByteArray:
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

func update_items(buffer:StreamPeerBuffer) -> void:
	var server_items = {}
	
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
		server_items[item_id] = true

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

func get_projectiles_state(buffer: StreamPeerBuffer) -> PoolByteArray:
	var main = $"/root/Main"
	
	var num_projectiles = 0 
	for child in main.get_children():
		if child is PlayerProjectile:
			num_projectiles += 1
			
	buffer.put_u16(num_projectiles)
	
	for child in main.get_children():
		if child is PlayerProjectile:
			buffer.put_32(child.id)
			
			buffer.put_float(child.position.x)
			buffer.put_float(child.position.y)
			
			buffer.put_float(child.global_position.x)
			buffer.put_float(child.global_position.y)
			
			buffer.put_float(child.rotation)
			
			# TODO send conditionally 
			buffer.put_string(child.filename)
	return buffer.data_array

func update_player_projectiles(buffer:StreamPeerBuffer) -> void:
	var server_player_projectiles = {}
	var num_projectiles = buffer.get_u16()
	
	for _projectile_index in num_projectiles:
		var projectile_id = buffer.get_32()
		
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		var position = Vector2(pos_x, pos_y)
		
		var global_pos_x = buffer.get_float()
		var global_pos_y = buffer.get_float()
		var global_position = Vector2(global_pos_x, global_pos_y)
		
		var rotation = buffer.get_float()
		
		var filename = buffer.get_string()
		
		if not client_player_projectiles.has(projectile_id):
			client_player_projectiles[projectile_id] = spawn_player_projectile(position, global_position, rotation, filename)
		
		var player_projectile = client_player_projectiles[projectile_id]
		if is_instance_valid(player_projectile):
			player_projectile.position = position
			player_projectile.rotation = rotation
		server_player_projectiles[projectile_id] = true
		
	for projectile_id in client_player_projectiles:
		if not server_player_projectiles.has(projectile_id):
			var player_projectile = client_player_projectiles[projectile_id]
			client_player_projectiles.erase(projectile_id)
			if is_instance_valid(player_projectile):
				get_tree().current_scene.remove_child(player_projectile)

func spawn_player_projectile(position:Vector2, global_position:Vector2, rotation:float, filename:String):
	var main = $"/root/ClientMain"
	var projectile = load(filename).instance()
	
	projectile.position = position
	projectile.spawn_position = global_position
	projectile.global_position = global_position
	projectile.rotation = rotation
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
			
func update_enemies(buffer:StreamPeerBuffer) -> void:
	var server_enemies = {}
	
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



func spawn_entity_birth(color:Color, position:Vector2):
	var entity_birth = entity_birth_scene.instance()
	
	entity_birth.color = color
	entity_birth.global_position = position
	
	$"/root/ClientMain/Entities".add_child(entity_birth)
	
	return entity_birth

func reset_client_items():
	client_enemies = {}
	client_births = {}
	client_players = {}
	client_items = {}
	client_player_projectiles = {}
	client_consumables = {}
	client_neutrals = {}

func get_enemies_state(buffer: StreamPeerBuffer) -> PoolByteArray:
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

func get_births_state(buffer: StreamPeerBuffer) -> PoolByteArray:
	var main = $"/root/Main"
	
	var num_births = main._entity_spawner.births.size()
	buffer.put_u16(num_births)
	
	for birth in main._entity_spawner.births:
		buffer.put_32(birth.id)
		
		buffer.put_float(birth.global_position.x)
		buffer.put_float(birth.global_position.y)
		
		buffer.put_float(birth.color.r)
		buffer.put_float(birth.color.g)
		buffer.put_float(birth.color.b)
		buffer.put_float(birth.color.a)
		
	return buffer.data_array

func update_births(buffer:StreamPeerBuffer) -> void:
	var server_births = {}
	var num_births = buffer.get_u16()
	
	for _birth_index in num_births:
		var birth_id = buffer.get_32()
		
		var x = buffer.get_float()
		var y = buffer.get_float()
		var r = buffer.get_float()
		var g = buffer.get_float()
		var b = buffer.get_float()
		var a = buffer.get_float()
		
		if not client_births.has(birth_id):
			client_births[birth_id] = spawn_entity_birth(Color(r,g,b,a), Vector2(x,y))
		server_births[birth_id] = true
		
	for birth_id in client_births:
		if not server_births.has(birth_id):
			var birth_to_delete = client_births[birth_id]
			if birth_to_delete:
#				Children go away on their own when they time out?
#				$"/root/ClientMain/Births".remove_child(birth_to_delete)
				client_births.erase(birth_id)


func get_players_state(buffer: StreamPeerBuffer) -> PoolByteArray:
	var tracked_players = parent.tracked_players
	
	var num_players = tracked_players.size()
	buffer.put_u16(num_players)
	
	for player_id in tracked_players:
		var tracked_player = tracked_players[player_id]["player"]
		buffer.put_64(player_id)
		
		buffer.put_float(tracked_player.position.x)
		buffer.put_float(tracked_player.position.y)
		
		buffer.put_float(tracked_player.current_stats.speed)
		
		buffer.put_float(tracked_player._current_movement.x)
		buffer.put_float(tracked_player._current_movement.y)
		
		buffer.put_u16(tracked_player.current_stats.health)
		buffer.put_u16(tracked_player.max_stats.health)

		# This would be where individual inventories are sent out instead of
		# RunData.gold
		buffer.put_u16(RunData.gold)

		var num_weapons = tracked_player.current_weapons.size()
		buffer.put_u16(num_weapons)
		
		for weapon in tracked_player.current_weapons:
			if not is_instance_valid(weapon):
				continue
			var weapon_data = {}
			
			buffer.put_float(weapon.sprite.position.x)
			buffer.put_float(weapon.sprite.position.y)
			
			buffer.put_float(weapon.sprite.rotation)
			
			buffer.put_8(weapon._is_shooting)

			if not sent_detail_ids.has(player_id):
				buffer.put_8(1)
				if weapon.has_node("data_node"):
					var weapon_data_path = RunData.weapon_paths[weapon.get_node("data_node").weapon_data.my_id]
					buffer.put_string(weapon_data_path)
#				TODO: uncomment this to stop writes, it'll cause problems later though
#				sent_detail_ids[player_id] = true
			else:
				buffer.put_8(0)

	return buffer.data_array

func update_players(buffer:StreamPeerBuffer) -> void:
	var tracked_players = parent.tracked_players
	
	var num_players = buffer.get_u16()
	
	for _player_index in num_players:
		var player_id = buffer.get_64()
		if not player_id in tracked_players:
			tracked_players[player_id] = {}
		
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		
		var speed = buffer.get_float()
		
		var mov_x = buffer.get_float()
		var mov_y = buffer.get_float()
		
		var current_health = buffer.get_u16()
		var max_health = buffer.get_u16()
		
		var gold = buffer.get_u16()
		
		var num_weapons = buffer.get_u16()
		
		var weapons = []
		for _weapon_index in num_weapons:
			var weapon = {}
			
			var weapon_pos_x = buffer.get_float()
			var weapon_pos_y = buffer.get_float()
			weapon["position"] = Vector2(weapon_pos_x, weapon_pos_y)
			
			var weapon_rotation = buffer.get_float()
			weapon["rotation"] = weapon_rotation
			
			var weapon_is_shooting = buffer.get_8()
			weapon["is_shooting"] = weapon_is_shooting
			
			var has_detail = buffer.get_8() == 1
			if has_detail:
				var weapon_path = buffer.get_string()
				weapon["path"] = weapon_path
			weapons.push_back(weapon)
				
		if not tracked_players[player_id].has("player") or not is_instance_valid(tracked_players[player_id].player):
			tracked_players[player_id]["player"] = spawn_player(player_id, Vector2(pos_x, pos_y), speed, weapons)
			
		var player = tracked_players[player_id]["player"]
		if player_id == parent.self_peer_id:
			if $"/root/ClientMain":
				var main = $"/root/ClientMain"
				main._life_bar.update_value(current_health, max_health)
				main.set_life_label(current_health, max_health)
				main._damage_vignette.update_from_hp(current_health, max_health)
				RunData.gold = gold
				$"/root/ClientMain"._ui_gold.on_gold_changed(gold)
		else:
			if is_instance_valid(player):
				player.position = Vector2(pos_x, pos_y)
				player.call_deferred("maybe_update_animation", Vector2(mov_x, mov_y), true)
		if is_instance_valid(player):
			for weapon_data_index in player.current_weapons.size():
				var weapon_data = weapons[weapon_data_index]
				var weapon = player.current_weapons[weapon_data_index]
				weapon.sprite.position = weapon_data.position
				weapon.sprite.rotation = weapon_data.rotation
				weapon._is_shooting = weapon_data.is_shooting

func spawn_player(player_id:int, position:Vector2, speed:float, weapons:Array):
	var spawned_player = player_scene.instance()
	spawned_player.position = position
	spawned_player.current_stats.speed = speed

	for weapon in weapons:
		spawned_player.call_deferred("add_weapon", load(weapon["path"]), spawned_player.current_weapons.size())

	$"/root/ClientMain/Entities".add_child(spawned_player)

	if player_id == parent.self_peer_id:
		spawned_player.get_remote_transform().remote_path = $"/root/ClientMain/Camera".get_path()
	spawned_player.call_deferred("remove_weapon_behaviors")

	return spawned_player

func get_consumables_state(buffer: StreamPeerBuffer) -> PoolByteArray:
	var main = $"/root/Main"
	
	var num_consumables = main._consumables_container.get_children().size()
	buffer.put_u16(num_consumables)
	
	for consumable in main._consumables_container.get_children():
		buffer.put_32(consumable.id)
		
		buffer.put_float(consumable.global_position.x)
		buffer.put_float(consumable.global_position.y)
	return buffer.data_array

func update_consumables(buffer:StreamPeerBuffer) -> void:
	var num_consumables = buffer.get_u16()
	
	var server_consumables = {}
	
	for _consumable_index in num_consumables:
		var consumable_id = buffer.get_32()
		
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		var position = Vector2(pos_x, pos_y)
		if not client_consumables.has(consumable_id):
			client_consumables[consumable_id] = spawn_consumable(position)
			
		var consumable = client_consumables[consumable_id]
		if is_instance_valid(consumable):
			consumable.global_position = position
		server_consumables[consumable_id] = true
	for consumable_id in client_consumables:
		if not server_consumables.has(consumable_id):
			var consumable = client_consumables[consumable_id]
			client_consumables.erase(consumable_id)
			if is_instance_valid(consumable):
				$"/root/ClientMain/Consumables".remove_child(consumable)

func spawn_consumable(position:Vector2):
	var consumable = consumable_scene.instance()
	
	consumable.global_position = position
	consumable.call_deferred("set_texture", consumable_texture)
	consumable.call_deferred("set_physics_process", false)
	
	$"/root/ClientMain/Consumables".add_child(consumable)
	
	return consumable

func get_neutrals_state(buffer: StreamPeerBuffer) -> PoolByteArray:
	var main = $"/root/Main"
	
	var num_neutrals = 0
	for neutral in main._entity_spawner.neutrals:
		if is_instance_valid(neutral):
			num_neutrals += 1
			
	buffer.put_u32(num_neutrals)
	
	for neutral in main._entity_spawner.neutrals:
		if is_instance_valid(neutral):
			var neutral_data = {}
			
			buffer.put_32(neutral.id)
			
			buffer.put_float(neutral.global_position.x)
			buffer.put_float(neutral.global_position.y)
	return buffer.data_array

func update_neutrals(buffer:StreamPeerBuffer) -> void:
	var server_neutrals = {}
	var num_neutrals = buffer.get_u32()
	for _neutral_index in num_neutrals:
		var neutral_id = buffer.get_32()
		
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		var position = Vector2(pos_x, pos_y)
		
		if not client_neutrals.has(neutral_id):
			client_neutrals[neutral_id] = spawn_neutral(position)
		var neutral = client_neutrals[neutral_id]
		if is_instance_valid(neutral):
			neutral.global_position = position
		server_neutrals[neutral_id] = true
	for neutral_id in client_neutrals:
		if not server_neutrals.has(neutral_id):
			var neutral = client_neutrals[neutral_id]
			client_neutrals.erase(neutral_id)
			if is_instance_valid(neutral):
				$"/root/ClientMain/Entities".remove_child(neutral)

func spawn_neutral(position:Vector2):
	var neutral = tree_scene.instance()
	neutral.global_position = position
	
	$"/root/ClientMain/Entities".add_child(neutral)
	
	return neutral
