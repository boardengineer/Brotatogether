extends Node

var client_enemies = {}
var client_births = {}
var client_players = {}
var client_items = {}
var client_player_projectiles = {}
var client_consumables = {}
var client_neutrals = {}
var client_structures = {}
var client_enemy_projectiles = {}

var parent
var run_updates = false

const gold_scene = preload("res://items/materials/gold.tscn")
const entity_birth_scene = preload("res://entities/birth/entity_birth.tscn")
const consumable_scene = preload("res://items/consumables/consumable.tscn")
const consumable_texture = preload("res://items/consumables/fruit/fruit.png")
const player_scene = preload("res://entities/units/player/player.tscn")

#TODO this is the sussiest of bakas
var weapon_stats_resource = ResourceLoader.load("res://weapons/ranged/pistol/1/pistol_stats.tres")
var turret_stats_resource = ResourceLoader.load("res://entities/structures/turret/turret_stats.tres")

# TODO all neutrals are going to be trees for now
const tree_scene = preload("res://entities/units/neutral/tree.tscn")

var ClientMovementBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_movement_behavior.gd")
var ClientAttackBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_attack_behavior.gd")

# TODO sometimes clear these
var sent_detail_ids = {}

const refresh_time = 1.0 / 30.0
var update_timer = refresh_time

func _physics_process(delta):
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return
		
	var game_controller = $"/root/GameController"
	update_timer -= delta
	var scene_name = get_tree().get_current_scene().get_name()
	
	if update_timer <= 0:
		update_timer = refresh_time
		if game_controller.is_host:
			if scene_name == "Main":
				if get_tree().get_current_scene().send_updates:
					game_controller.call_deferred("send_game_state")
	
	while read_p2p_packet():
			pass

func read_p2p_packet() -> bool:
	var packet_size = Steam.getAvailableP2PPacketSize(1)
	
	if packet_size > 0:
		var packet = Steam.readP2PPacket(packet_size, 1)
		
		var data = bytes2var(packet["data"].decompress_dynamic(-1, File.COMPRESSION_GZIP))
		var type = data.type
		
		if type == "game_state":
			parent.update_game_state(data.game_state)
		return true
	return false

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
			get_structures_state(buffer)
			get_enemy_projectiles(buffer)
			get_deaths(buffer)
			get_enemy_damages(buffer)
			get_enemy_flashes(buffer)
			get_batched_floating_text(buffer)
			get_hit_effects(buffer)
			
			buffer.put_float(main._wave_timer.time_left)
			buffer.put_32(RunData.bonus_gold)
	
	return buffer.data_array

func update_game_state(data: PoolByteArray) -> void:
	var main = get_tree().get_current_scene()
	if main.get_name() != "ClientMain":
		return
	
	var buffer = StreamPeerBuffer.new()
	buffer.data_array = data
	
	update_players(buffer)
	
	var enemies_arrays = get_enemies_arrays(buffer)
	call_deferred("update_enemies", enemies_arrays)
	
	update_births(buffer)
	update_items(buffer)
	
	var player_projectiles_array = get_player_projectiles_array(buffer)
	call_deferred("update_player_projectiles", player_projectiles_array)
	
	update_consumables(buffer)
	update_neutrals(buffer)
	update_structures(buffer)
	update_enemy_projectiles(buffer)
	
	var batched_deaths = get_batched_deaths(buffer)
	var batched_damages = get_batched_damages(buffer)
	var batched_flashes = get_batched_flashes(buffer)
	var batched_floating_text = get_batched_text_array(buffer)
	var batched_hit_effects = get_batch_hit_effects_array(buffer)
	
	call_deferred("do_batched_deaths", batched_deaths)
	call_deferred("do_batched_damages", batched_damages)
	call_deferred("do_batched_flashes", batched_flashes)
	call_deferred("do_batched_floating_text", batched_floating_text)
	call_deferred("do_batched_hit_effects", batched_hit_effects)
	
	var _time = buffer.get_float()
	main._wave_timer.start(_time)
	
	var bonus_gold = buffer.get_32()
	if bonus_gold > 0:
		main._ui_bonus_gold.show()
		main._ui_bonus_gold.update_value(bonus_gold)
	else:
		main._ui_bonus_gold.hide()

func get_enemy_projectiles(buffer: StreamPeerBuffer) -> void:
	var projectiles_container = $"/root/Main/Projectiles"
	var main = $"/root/Main"
	var entity_spawner = main._entity_spawner
	
	var num_projectiles = projectiles_container.get_children().size()
	
	for enemy in entity_spawner.enemies:
		if enemy.has_node("Pivot"):
			for projectile in enemy.get_node("Pivot").get_children():
				if projectile is EnemyProjectile:
					num_projectiles += 1
					
	for boss in entity_spawner.bosses:
		if boss.has_node("Pivot"):
			for projectile in boss.get_node("Pivot").get_children():
				if projectile is EnemyProjectile:
					num_projectiles += 1
	
	buffer.put_u16(num_projectiles)

	for projectile in projectiles_container.get_children():
		encode_projectile(buffer, projectile)
		
	for enemy in entity_spawner.enemies:
		if enemy.has_node("Pivot"):
			for projectile in enemy.get_node("Pivot").get_children():
				if projectile is EnemyProjectile:
					encode_projectile(buffer, projectile)
					
	for boss in entity_spawner.bosses:
		if boss.has_node("Pivot"):
			for projectile in boss.get_node("Pivot").get_children():
				if projectile is EnemyProjectile:
					encode_projectile(buffer, projectile)
			
func encode_projectile(buffer: StreamPeerBuffer, projectile) -> void:
	buffer.put_32(projectile.network_id)
		
	buffer.put_float(projectile.position.x)
	buffer.put_float(projectile.position.y)
		
	buffer.put_float(projectile.global_position.x)
	buffer.put_float(projectile.global_position.y)
		
	buffer.put_float(projectile.rotation)
		
	if not sent_detail_ids.has(projectile.network_id):
		buffer.put_8(1)
		
		buffer.put_string(projectile.filename)
		
		sent_detail_ids[projectile.network_id] = true
	else:
		buffer.put_8(0)

func update_enemy_projectiles(buffer:StreamPeerBuffer) -> void:
	var server_enemy_projectiles = {}
	
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
		
		var has_detail = buffer.get_8() == 1
		
		var filename = ""
		
		if has_detail:
			filename = buffer.get_string()
			
		if not client_enemy_projectiles.has(projectile_id):
			if filename.empty():
				continue
			client_enemy_projectiles[projectile_id] = spawn_enemy_projectile(position, global_position, rotation, filename)
		if is_instance_valid(client_enemy_projectiles[projectile_id]):
			client_enemy_projectiles[projectile_id].position = position
			client_enemy_projectiles[projectile_id].global_position = global_position
		server_enemy_projectiles[projectile_id] = true

	for projectile_id in client_enemy_projectiles:
		if not server_enemy_projectiles.has(projectile_id):
			var projectile = client_enemy_projectiles[projectile_id]
			if not client_enemy_projectiles[projectile_id]:
				continue

			client_enemy_projectiles.erase(projectile_id)
			if not $"/root/ClientMain/Projectiles":
				continue 
			if not projectile:
				continue
			if not is_instance_valid(projectile):
				continue
				
			# This sometimes throws a C++ error
			$"/root/ClientMain/Projectiles".remove_child(projectile)

func spawn_enemy_projectile(position:Vector2, global_position:Vector2, rotation:float, filename:String):
	var projectiles_container = $"/root/ClientMain/Projectiles"
	var projectile = load(filename).instance()
	
	projectile.position = position
	projectile.global_position = global_position
	projectile.rotation = rotation
	
	projectile.set_physics_process(false)
	
	projectiles_container.add_child(projectile, true)
	
	projectile.call_deferred("set_physics_process", false)
	
	return projectile


func get_items_state(buffer: StreamPeerBuffer) -> void:
	var main = $"/root/Main"
	
	var num_items = main._items_container.get_children().size()
	buffer.put_u16(num_items)
	
	for item in main._items_container.get_children():
		buffer.put_32(item.get_network_id())
		buffer.put_float(item.global_position.x)
		buffer.put_float(item.global_position.y)
				
		if not sent_detail_ids.has(item.get_network_id()):
			buffer.put_8(1)
			
			buffer.put_float(item.scale.x)
			buffer.put_float(item.scale.y)
			
			buffer.put_float(item.rotation)
			
			buffer.put_float(item.push_back_destination.x)
			buffer.put_float(item.push_back_destination.y)
			
			sent_detail_ids[item.get_network_id()] = true
		else:
			buffer.put_8(0)

		# TODO we may want textures propagated

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
			if not is_instance_valid(item):
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

func get_projectiles_state(buffer: StreamPeerBuffer) -> void:
	var main = $"/root/Main"
	
	var num_projectiles = 0 
	for child in main.get_children():
		if child is PlayerProjectile:
			num_projectiles += 1
			
	buffer.put_u16(num_projectiles)
	
	for child in main.get_children():
		if child is PlayerProjectile:
			buffer.put_32(child.get_network_id())
			
			buffer.put_float(child.position.x)
			buffer.put_float(child.position.y)
			
			buffer.put_float(child.global_position.x)
			buffer.put_float(child.global_position.y)
			
			buffer.put_float(child.rotation)
			
			# TODO send conditionally 
			buffer.put_string(child.filename)


func get_player_projectiles_array(buffer:StreamPeerBuffer) -> Array:
	var server_player_projectiles = {}
	
	var player_projectiles_array = []
	var num_projectiles = buffer.get_u16()
	
	for _projectile_index in num_projectiles:
		var projectile_id = buffer.get_32()
		
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		
		var global_pos_x = buffer.get_float()
		var global_pos_y = buffer.get_float()
		
		var rotation = buffer.get_float()
		var filename = buffer.get_string()
		
		if filename == "":
			continue
		
		player_projectiles_array.push_back([projectile_id, pos_x, pos_y, global_pos_x, global_pos_y, rotation, filename])
	
	return player_projectiles_array


func update_player_projectiles(player_projectiles_array:Array) -> void:
	var server_player_projectiles = {}
	
	for player_projectile in player_projectiles_array:
		var projectile_id = player_projectile[0]
		
		var pos_x = player_projectile[1]
		var pos_y = player_projectile[2]
		var position = Vector2(pos_x, pos_y)
		
		var global_pos_x = player_projectile[3]
		var global_pos_y = player_projectile[4]
		var global_position = Vector2(global_pos_x, global_pos_y)
		
		var rotation = player_projectile[5]
		var filename = player_projectile[6]
		
		if filename == "":
			continue
		
		if not client_player_projectiles.has(projectile_id):
			client_player_projectiles[projectile_id] = spawn_player_projectile(position, global_position, rotation, filename)
		
		var client_player_projectile = client_player_projectiles[projectile_id]
		if is_instance_valid(client_player_projectile):
			client_player_projectile.position = position
			client_player_projectile.rotation = rotation
		server_player_projectiles[projectile_id] = true
		
	for projectile_id in client_player_projectiles.keys():
		if not server_player_projectiles.has(projectile_id):
			var player_projectile = client_player_projectiles[projectile_id]
			client_player_projectiles.erase(projectile_id)
			if is_instance_valid(player_projectile):
				player_projectile.queue_free()


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

func get_deaths(buffer: StreamPeerBuffer) -> void:
	var num_deaths = parent.batched_deaths.size()
	buffer.put_u16(num_deaths)
	
	for enemy_id in parent.batched_deaths:
		buffer.put_32(enemy_id)
	
	parent.batched_deaths = []

func get_batched_deaths(buffer:StreamPeerBuffer) -> Array:
	var result = []
	var num_deaths = buffer.get_u16()
	for _i in num_deaths:
		result.push_back(buffer.get_32())
	return result

func do_batched_deaths(death_ids : Array) -> void:
	for enemy_id in death_ids:
		enemy_death(enemy_id)

func enemy_death(enemy_id):
	if client_enemies.has(enemy_id):
		if is_instance_valid(client_enemies[enemy_id]):
			client_enemies[enemy_id].die()

func get_enemy_damages(buffer: StreamPeerBuffer) -> void:
	var num_damages = parent.batched_enemy_damage.size()
	buffer.put_u16(num_damages)
	
	for damage_array in parent.batched_enemy_damage:
		buffer.put_32(damage_array[0])
		var is_dodge = 0
		if damage_array[1]:
			is_dodge = 1
		buffer.put_8(is_dodge)
	
	parent.batched_enemy_damage = []

func get_batched_damages(buffer:StreamPeerBuffer) -> Array:
	var result = []
	var num_damages = buffer.get_u16()
	for _i in num_damages:
		var enemy_id = buffer.get_32()
		var is_dodge = buffer.get_8() == 1
		result.push_back([enemy_id, is_dodge])
	return result

func do_batched_damages(batched_damages: Array) -> void:
	for damage in batched_damages:
		var enemy_id = damage[0]
		var is_dodge = damage[1]
		do_enemy_damage(enemy_id, is_dodge)

func do_enemy_damage(enemy_id:int, is_dodge:bool) -> void:
	if not is_inside_tree():
		return
	if client_enemies.has(enemy_id):
		var enemy = client_enemies[enemy_id]
		if is_instance_valid(enemy):
			var sound
			if is_dodge:
				sound = Utils.get_rand_element(enemy.dodge_sounds)
			else:
				sound = Utils.get_rand_element(enemy.hurt_sounds)
			SoundManager2D.play(sound, enemy.global_position, 0, 0.2, enemy.always_play_hurt_sound)

func get_enemy_flashes(buffer: StreamPeerBuffer) -> void:
	var num_flashes = parent.batched_flash_enemy.size()
	buffer.put_u16(num_flashes)
	
	for enemy_id in parent.batched_flash_enemy:
		buffer.put_32(enemy_id)
	
	parent.batched_flash_enemy = []

func get_batched_flashes(buffer:StreamPeerBuffer) -> Array:
	var result = []
	var num_flashes = buffer.get_u16()
	
	for _i in num_flashes:
		var enemy_id = buffer.get_32()
		result.push_back(enemy_id)
	return result

func do_batched_flashes(batched_flashes: Array) -> void:
	for enemy_id in batched_flashes:
		flash_enemy(enemy_id)

func flash_enemy(enemy_id):
	if not is_inside_tree():
		return
	if client_enemies.has(enemy_id):
		if is_instance_valid(client_enemies[enemy_id]):
			client_enemies[enemy_id].flash()

func get_batched_floating_text(buffer: StreamPeerBuffer) -> void:
	var num_floating_text = parent.batched_floating_text.size()
	buffer.put_u16(num_floating_text)
	
	for floating_text_array in parent.batched_floating_text:
		var value = floating_text_array[0]
		var text_pos = floating_text_array[1]
		var color = floating_text_array[2]
		
		buffer.put_string(value)
		buffer.put_float(text_pos.x)
		buffer.put_float(text_pos.y)
		buffer.put_32(color.to_rgba32())
	
	parent.batched_floating_text = []

func get_batched_text_array(buffer: StreamPeerBuffer) -> Array:
	var result = []
	var num_floating_text = buffer.get_u16()
	
	for _i in num_floating_text:
		var value = buffer.get_string()
		
		var x = buffer.get_float()
		var y = buffer.get_float()
		var text_pos = Vector2(x,y)
		
		var color_rgba32 = buffer.get_32()
		var color = Color(color_rgba32)
		result.push_back([value, text_pos, color])
	return result

func do_batched_floating_text(text_array: Array) -> void:
	for text in text_array:
		display_floating_text(text[0], text[1], text[2])

func display_floating_text(value:String, text_pos:Vector2, color:Color = Color.white):
	if $"/root/ClientMain":
		$"/root/ClientMain/FloatingTextManager".display(value, text_pos, color)

func get_hit_effects(buffer: StreamPeerBuffer) -> void:
	var num_hit_effects = parent.batched_hit_effects.size()
	buffer.put_u16(num_hit_effects)
	
	for hit_effect in parent.batched_hit_effects:
		buffer.put_float(hit_effect[0].x)
		buffer.put_float(hit_effect[0].y)
		
		buffer.put_float(hit_effect[1].x)
		buffer.put_float(hit_effect[1].y)
		
		buffer.put_float(hit_effect[2])
	parent.batched_hit_effects = []

func get_batch_hit_effects_array(buffer: StreamPeerBuffer) -> Array:
	var result = []
	var num_hit_effects = buffer.get_u16()
	
	for _i in num_hit_effects:
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		
		var dir_x = buffer.get_float()
		var dir_y = buffer.get_float()
		
		var scale = buffer.get_float()
		var pos = Vector2(pos_x, pos_y)
		var dir = Vector2(dir_x, dir_y)
		result.push_back([pos, dir, scale])
	return result

func do_batched_hit_effects(hit_effects_array: Array) -> void:
	for hit_effect in hit_effects_array:
		display_hit_effect(hit_effect[0], hit_effect[1], hit_effect[2])

func display_hit_effect(position, direction, scale):
	if $"/root/ClientMain/EffectsManager":
		var effects_manager = $"/root/ClientMain/EffectsManager"
		effects_manager.play_hit_particles(position, direction, scale)
		effects_manager.play_hit_effect(position, direction, scale)

func flash_neutral(neutral_id):
	if client_neutrals.has(neutral_id):
		if is_instance_valid(client_neutrals[neutral_id]):
			client_neutrals[neutral_id].flash()

func get_enemies_state(buffer: StreamPeerBuffer) -> void:
	var main = $"/root/Main"
	var entity_spawner = main._entity_spawner
	
	var num_enemies = entity_spawner.enemies.size()
	buffer.put_u16(num_enemies)
	
	for enemy in entity_spawner.enemies:
		if is_instance_valid(enemy):
				var network_id = enemy.get_network_id()
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
				
	var num_bosses = entity_spawner.bosses.size()
	buffer.put_u16(num_bosses)
	
	for enemy in entity_spawner.bosses:
		if is_instance_valid(enemy):
				var network_id = enemy.get_network_id()
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
				
				buffer.put_32(enemy.current_stats.health)
				buffer.put_32(enemy.max_stats.health)

func get_enemies_arrays(buffer:StreamPeerBuffer) -> Array:
	var enemies_array = []
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
		enemies_array.push_back([enemy_id, filename, resource_path, pos_x, pos_y, mov_x, mov_y])
	
	var bosses_array = []
	var num_bosses = buffer.get_u16()
	for _enemy_index in num_bosses:
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
		var current_hp = buffer.get_32()
		var max_hp = buffer.get_32()
		bosses_array.push_back([enemy_id, filename, resource_path, pos_x, pos_y, mov_x, mov_y, current_hp, max_hp])
	
	return [enemies_array, bosses_array]

func update_enemies(enemies_arrays: Array) -> void:
	var server_enemies = {}
	
	for enemy in enemies_arrays[0]:
		var enemy_id = enemy[0]
		var filename = enemy[1]
		var resource_path = enemy[2]
		
		var pos_x = enemy[3]
		var pos_y = enemy[4]
		var mov_x = enemy[5]
		var mov_y = enemy[6]
		
		var position = Vector2(pos_x, pos_y)
		var movement = Vector2(mov_x, mov_y)
		
		if not client_enemies.has(enemy_id):
			if filename == "":
				continue
			call_deferred("spawn_enemy", enemy_id, position, filename, resource_path)
		
		if client_enemies.has(enemy_id):
			var stored_enemy = client_enemies[enemy_id]
			if is_instance_valid(stored_enemy):
				server_enemies[enemy_id] = true
				stored_enemy.position = position
				stored_enemy.call_deferred("update_animation", movement)
	
	for boss in enemies_arrays[1]:
		var enemy_id = boss[0]
		var filename = boss[1]
		var resource_path = boss[2]
		
		var pos_x = boss[3]
		var pos_y = boss[4]
		var mov_x = boss[5]
		var mov_y = boss[6]
		
		var current_hp = boss[7]
		var max_hp = boss[8]
		
		var position = Vector2(pos_x, pos_y)
		var movement = Vector2(mov_x, mov_y)
		
		if not client_enemies.has(enemy_id):
			if filename == "":
				continue
			call_deferred("spawn_enemy", enemy_id, position, filename, resource_path)
			
		if client_enemies.has(enemy_id):
			var stored_enemy = client_enemies[enemy_id]
			if is_instance_valid(stored_enemy):
				server_enemies[enemy_id] = true
				stored_enemy.position = position
				stored_enemy.on_health_updated(current_hp, max_hp)
				stored_enemy.call_deferred("update_animation", movement)


func spawn_enemy(enemy_id, position:Vector2, filename:String, resource_path:String):
	var entity = load(filename).instance()

	entity.position = position
	entity.stats = load(resource_path)

	_clear_movement_behavior(entity)

	$"/root/ClientMain/Entities".add_child(entity)

	client_enemies[enemy_id] = entity


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

func get_structures_state(buffer: StreamPeerBuffer) -> void:
	var main = $"/root/Main"
	var entity_spawner = main._entity_spawner
	
	var num_structures = entity_spawner.structures.size()
	buffer.put_u16(num_structures)
	
	for structure in entity_spawner.structures:
		if is_instance_valid(structure):
			var structure_id = structure.network_id
			buffer.put_32(structure_id)
			
			# TODO only send spawn info once
			if not sent_detail_ids.has(structure_id):
				buffer.put_8(1)
				buffer.put_string(structure.filename)
			else:
				buffer.put_8(0)
			
			buffer.put_float(structure.position.x)
			buffer.put_float(structure.position.y)

func update_structures(buffer:StreamPeerBuffer) -> void:
	var server_structures = {}
	
	var num_structures = buffer.get_u16()
	
	for _structure_index in num_structures:
		var structure_id = buffer.get_32()
		var has_filename = buffer.get_8() == 1
		var filename = ""
		
		if has_filename:
			filename = buffer.get_string()
		
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		
		var position = Vector2(pos_x, pos_y)
		
		if not client_structures.has(structure_id):
			if not has_filename:
				continue
			var enemy = spawn_stucture(position, filename)
			client_structures[structure_id] = enemy
			
		var stored_structure = client_structures[structure_id]
		if is_instance_valid(stored_structure):
			server_structures[structure_id] = true
			stored_structure.position = position
			
	for structure_id in client_structures:
		if not server_structures.has(structure_id):
			var structure = client_structures[structure_id]
			client_structures.erase(structure_id)
			if is_instance_valid(structure) and $"/root/ClientMain/Entities".is_a_parent_of(structure):
				$"/root/ClientMain/Entities".remove_child(structure)

func spawn_stucture(position:Vector2, filename:String):
	var structure = load(filename).instance()

	structure.position = position
	structure.stats = turret_stats_resource

	$"/root/ClientMain/Entities".add_child(structure)

	return structure

func get_births_state(buffer: StreamPeerBuffer) -> void:
	var main = $"/root/Main"
	
	var num_births = main._entity_spawner.births.size()
	buffer.put_u16(num_births)
	
	for birth in main._entity_spawner.births:
		if is_instance_valid(birth) and birth.is_inside_tree() and birth.get_node("data_node") != null:
			buffer.put_32(birth.get_network_id())
			
			buffer.put_float(birth.global_position.x)
			buffer.put_float(birth.global_position.y)
			
			buffer.put_float(birth.color.r)
			buffer.put_float(birth.color.g)
			buffer.put_float(birth.color.b)
			buffer.put_float(birth.color.a)
		else:
			buffer.put_32(1)
			
			buffer.put_float(0.0)
			buffer.put_float(0.0)
			
			buffer.put_float(0.0)
			buffer.put_float(0.0)
			buffer.put_float(0.0)
			buffer.put_float(0.0)

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


func get_players_state(buffer: StreamPeerBuffer) -> void:
	var tracked_players = parent.tracked_players
	var num_players = tracked_players.size()
	buffer.put_u16(num_players)
	
	for player_id in tracked_players:
		var tracked_player = tracked_players[player_id]["player"]
		var run_data = tracked_players[player_id]["run_data"]
		
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
		buffer.put_u16(run_data.gold)
		buffer.put_u16(run_data.current_level)
		buffer.put_u16(run_data.current_xp)
#		print_debug("sending gold for player ", player_id, " ", run_data.gold)
		
		var num_appearances = run_data.appearances_displayed.size()
		buffer.put_u16(num_appearances)
		
		for appearance in run_data.appearances_displayed:
			buffer.put_string(appearance.resource_path) 

		var num_weapons = tracked_player.current_weapons.size()
		buffer.put_u16(num_weapons)
		
		for weapon in tracked_player.current_weapons:
			if not is_instance_valid(weapon):
				continue
			buffer.put_float(weapon.sprite.position.x)
			buffer.put_float(weapon.sprite.position.y)
			
			buffer.put_float(weapon.sprite.rotation)
			
			buffer.put_8(weapon._is_shooting)

			if not sent_detail_ids.has(player_id):
				buffer.put_8(1)
				if weapon.has_node("data_node"):
					var weapon_data_path = RunData.weapon_paths[weapon.get_node("data_node").weapon_data.my_id]
					buffer.put_string(weapon_data_path)
#					print_debug("sending data path ", weapon.get_node("data_node").weapon_data.my_id, " ", weapon_data_path)
#				TODO: uncomment this to stop writes, it'll cause problems later though
#				sent_detail_ids[player_id] = true
			else:
				buffer.put_8(0)

func update_players(buffer:StreamPeerBuffer) -> void:
	var tracked_players = parent.tracked_players
	
	var num_players = buffer.get_u16()
	
	for _player_index in num_players:
		var player_id = buffer.get_64()
		if not player_id in tracked_players:
			tracked_players[player_id] = {}
			parent.init_player_data(tracked_players[player_id], player_id)
		
		var run_data = tracked_players[player_id]["run_data"]
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		
		var speed = buffer.get_float()
		
		var mov_x = buffer.get_float()
		var mov_y = buffer.get_float()
		
		var current_health = buffer.get_u16()
		var max_health = buffer.get_u16()
		
		var gold = buffer.get_u16()
		var current_level = buffer.get_16()
		var current_xp = buffer.get_16()
		
		var num_appearances = buffer.get_u16()
		var appeareances_filenames = []
		
		# TODO This should be part of spawning only
		for _appearance_index in num_appearances:
			appeareances_filenames.push_back(buffer.get_string())
		
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
			tracked_players[player_id]["player"] = spawn_player(player_id, Vector2(pos_x, pos_y), speed, weapons, appeareances_filenames)
			
		var player = tracked_players[player_id]["player"]
		if player_id == parent.self_peer_id:
			if $"/root/ClientMain":
				var main = $"/root/ClientMain"
				
				main._life_bar.update_value(current_health, max_health)
				main.set_life_label(current_health, max_health)
				main._damage_vignette.update_from_hp(current_health, max_health)
				
				if is_instance_valid(player): 
					player.current_stats.health = current_health
					player.max_stats.health = max_health
				
				tracked_players[player_id]["current_health"] = current_health
				tracked_players[player_id]["max_health"] = max_health
				
				if run_data.gold != gold:
					run_data.gold = gold
					if player_id == parent.self_peer_id:
						$"/root/ClientMain"._ui_gold.on_gold_changed(gold)
				
				if run_data.current_xp != current_xp:
					run_data.current_xp = current_xp
					var next_level_xp = RunData.get_xp_needed(current_level + 1)
					if player_id == parent.self_peer_id:
						$"/root/ClientMain"._xp_bar.update_value(current_xp, next_level_xp)
					
#				TODO this should only be set once but it seems the run_data is set elsewhere
				run_data.current_level = current_level
				$"/root/ClientMain"._level_label.text = "LV." + str(current_level)
		else:
			if is_instance_valid(player):
				player.position = Vector2(pos_x, pos_y)
				
				# This is currently only used by the hp tracker bar 
				player.current_stats.health = current_health
				player.max_stats.health = max_health
				
				player.call_deferred("maybe_update_animation", Vector2(mov_x, mov_y), true)
		if is_instance_valid(player):
			for weapon_data_index in player.current_weapons.size():
				var weapon_data = weapons[weapon_data_index]
				var weapon = player.current_weapons[weapon_data_index]
				if is_instance_valid(weapon):
					weapon.sprite.position = weapon_data.position
					weapon.sprite.rotation = weapon_data.rotation
					weapon._is_shooting = weapon_data.is_shooting

func spawn_player(player_id:int, position:Vector2, speed:float, weapons:Array, appeareances_filenames: Array):
	var spawned_player = player_scene.instance()
	spawned_player.position = position
	spawned_player.current_stats.speed = speed
	spawned_player.call_deferred("init", Vector2(0,0), Vector2(0,0))

	for weapon in weapons:
		spawned_player.call_deferred("add_weapon", load(weapon["path"]), spawned_player.current_weapons.size())

	$"/root/ClientMain/Entities".add_child(spawned_player)

	if player_id == parent.self_peer_id:
		spawned_player.get_remote_transform().remote_path = $"/root/ClientMain/Camera".get_path()
	else:
		spawned_player.call_deferred("remove_movement_behavior")
	
	spawned_player.call_deferred("remove_weapon_behaviors")

	for filename in appeareances_filenames:
		var item_sprite = Sprite.new()
		item_sprite.texture = load(filename).sprite
		spawned_player.get_node("Animation").add_child(item_sprite)

	return spawned_player

func get_consumables_state(buffer: StreamPeerBuffer) -> void:
	var main = $"/root/Main"
	
	var num_consumables = main._consumables_container.get_children().size()
	buffer.put_u16(num_consumables)
	
	for consumable in main._consumables_container.get_children():
		buffer.put_32(consumable.get_network_id())
		
		buffer.put_float(consumable.global_position.x)
		buffer.put_float(consumable.global_position.y)
		
		buffer.put_string(consumable.consumable_data.icon.load_path)

func update_consumables(buffer:StreamPeerBuffer) -> void:
	var num_consumables = buffer.get_u16()
	
	var server_consumables = {}
	
	for _consumable_index in num_consumables:
		var consumable_id = buffer.get_32()
		
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		var position = Vector2(pos_x, pos_y)
		
		var texture_path = buffer.get_string()
		
		if not client_consumables.has(consumable_id):
			client_consumables[consumable_id] = spawn_consumable(position, texture_path)
			
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

func spawn_consumable(position:Vector2, filepath:String):
	var consumable = consumable_scene.instance()
	
	consumable.global_position = position
	consumable.call_deferred("set_texture", load(filepath))
	consumable.call_deferred("set_physics_process", false)
	
	$"/root/ClientMain/Consumables".add_child(consumable)
	
	return consumable

func get_neutrals_state(buffer: StreamPeerBuffer) -> void:
	var main = $"/root/Main"
	
	var num_neutrals = 0
	for neutral in main._entity_spawner.neutrals:
		if is_instance_valid(neutral):
			num_neutrals += 1
			
	buffer.put_u16(num_neutrals)
	
	for neutral in main._entity_spawner.neutrals:
		if is_instance_valid(neutral):
			buffer.put_32(neutral.get_network_id())
			
			buffer.put_float(neutral.global_position.x)
			buffer.put_float(neutral.global_position.y)

func update_neutrals(buffer:StreamPeerBuffer) -> void:
	var server_neutrals = {}
	var num_neutrals = buffer.get_u16()
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
			if is_instance_valid(neutral) and $"/root/ClientMain/Entities".is_a_parent_of(neutral):
				$"/root/ClientMain/Entities".remove_child(neutral)

func spawn_neutral(position:Vector2):
	var neutral = tree_scene.instance()
	neutral.global_position = position
	
	$"/root/ClientMain/Entities".add_child(neutral)
	
	return neutral
