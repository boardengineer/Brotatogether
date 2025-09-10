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

var weapon_stats_resource = ResourceLoader.load("res://weapons/ranged/pistol/1/pistol_stats.tres")
var turret_stats_resource = ResourceLoader.load("res://entities/structures/turret/turret_stats.tres")

const tree_scene = preload("res://entities/units/neutral/tree.tscn")

var ClientMovementBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_movement_behavior.gd")
var ClientAttackBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_attack_behavior.gd")

var sent_detail_ids = {}

const refresh_time = 1.0 / 30.0
var update_timer = refresh_time

func _physics_process(delta):
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return
		
	var game_controller = $"/root/GameController"
	update_timer -= delta
	
	if update_timer <= 0:
		update_timer = refresh_time
		if game_controller.is_host and game_controller.tracked_players.size() <= 4:
			var scene_name = get_tree().get_current_scene().get_name()
			if scene_name == "Main" and get_tree().get_current_scene().send_updates:
				game_controller.call_deferred("send_game_state")
	
	while read_p2p_packet():
		pass

func read_p2p_packet() -> bool:
	var packet_size = Steam.getAvailableP2PPacketSize(0)
	if packet_size > 0:
		var packet = Steam.readP2PPacket(packet_size, 0)
		var data = bytes2var(packet["data"].decompress_dynamic(-1, File.COMPRESSION_GZIP))
		var sender = packet["steam_id_remote"]
		if data.type == "game_state":
			update_game_state(data.data)
		return true
	return false

func get_game_state(buffer: StreamPeerBuffer):
	var main = $"/root/Main"
	get_players_state(buffer)
	get_enemies_state(buffer)
	get_births_state(buffer)
	get_items_state(buffer)
	get_player_projectiles_state(buffer)
	get_consumables_state(buffer)
	get_neutrals_state(buffer)
	get_structures_state(buffer)
	get_enemy_projectiles_state(buffer)
	get_batched_deaths(buffer)
	get_batched_damages(buffer)
	get_batched_flashes(buffer)
	get_batched_floating_text(buffer)
	get_batched_hit_effects(buffer)
	buffer.put_u16(main._ui_gold._gold)
	buffer.put_32(main._ui_bonus_gold._value)

func update_game_state(data: PoolByteArray) -> void:
	var main = get_tree().get_current_scene()
	if main.get_name() != "ClientMain":
		return
	var buffer = StreamPeerBuffer.new()
	buffer.data_array = data
	update_players(buffer)
	update_enemies(get_enemies_arrays(buffer))
	update_births(buffer)
	update_items(buffer)
	update_player_projectiles(get_player_projectiles_array(buffer))
	update_consumables(buffer)
	update_neutrals(buffer)
	update_structures(buffer)
	update_enemy_projectiles(buffer)
	do_batched_deaths(get_batched_deaths(buffer))
	do_batched_damages(get_batched_damages(buffer))
	do_batched_flashes(get_batched_flashes(buffer))
	do_batched_floating_text(get_batched_text_array(buffer))
	do_batched_hit_effects(get_batch_hit_effects_array(buffer))
	main._ui_gold.on_gold_changed(buffer.get_u16())
	main._ui_bonus_gold.update_value(buffer.get_32())
	main._ui_upgrades_to_process.queue_redraw()

func update_enemies(enemies_arrays: Array) -> void:
	var server_enemies = {}
	for enemy in enemies_arrays[0]:
		var enemy_id = enemy[0]
		if not client_enemies.has(enemy_id):
			if enemy[1] == "":
				continue
			call_deferred("spawn_enemy", enemy_id, Vector2(enemy[3], enemy[4]), enemy[1], enemy[2])
		if client_enemies.has(enemy_id) and is_instance_valid(client_enemies[enemy_id]):
			server_enemies[enemy_id] = true
			client_enemies[enemy_id].position = Vector2(enemy[3], enemy[4])
			client_enemies[enemy_id].call_deferred("update_animation", Vector2(enemy[5], enemy[6]))
	for enemy_id in client_enemies.keys():
		if not server_enemies.has(enemy_id) and is_instance_valid(client_enemies[enemy_id]):
			client_enemies[enemy_id].queue_free()
			client_enemies.erase(enemy_id)

func spawn_enemy(enemy_id: int, position: Vector2, filepath: String, stats_resource):
	var enemy = load(filepath).instance()
	enemy.global_position = position
	enemy.stats = stats_resource
	$"/root/ClientMain/Entities".add_child(enemy)
	client_enemies[enemy_id] = enemy
	return enemy

func update_players(buffer: StreamPeerBuffer):
	var num_players = buffer.get_u16()
	for _i in num_players:
		var player_id = buffer.get_32()
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		var position = Vector2(pos_x, pos_y)
		if not client_players.has(player_id):
			client_players[player_id] = spawn_player(position)
		var player = client_players[player_id]
		if is_instance_valid(player):
			player.global_position = position

func spawn_player(position: Vector2):
	var player = player_scene.instance()
	player.global_position = position
	player.set_movement_behavior(ClientMovementBehavior.new().init(player))
	player.set_attack_behavior(ClientAttackBehavior.new())
	$"/root/ClientMain/Entities".add_child(player)
	return player

func update_births(buffer: StreamPeerBuffer):
	var num_births = buffer.get_u16()
	for _i in num_births:
		var birth_id = buffer.get_32()
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		var filepath = buffer.get_string()
		if not client_births.has(birth_id):
			client_births[birth_id] = spawn_birth(Vector2(pos_x, pos_y), filepath)

func spawn_birth(position: Vector2, filepath: String):
	var birth = entity_birth_scene.instance()
	birth.global_position = position
	birth.call_deferred("set_entity", load(filepath))
	$"/root/ClientMain/Entities".add_child(birth)
	return birth

func update_items(buffer: StreamPeerBuffer):
	var num_items = buffer.get_u16()
	for _i in num_items:
		var item_id = buffer.get_32()
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		var filepath = buffer.get_string()
		if not client_items.has(item_id):
			client_items[item_id] = spawn_item(Vector2(pos_x, pos_y), filepath)

func spawn_item(position: Vector2, filepath: String):
	var item = load(filepath).instance()
	item.global_position = position
	$"/root/ClientMain/Items".add_child(item)
	return item

func update_player_projectiles(projectiles_array: Array):
	var server_projectiles = {}
	for projectile in projectiles_array:
		var proj_id = projectile[0]
		if not client_player_projectiles.has(proj_id):
			client_player_projectiles[proj_id] = spawn_projectile(Vector2(projectile[2], projectile[3]), projectile[1])
		var proj = client_player_projectiles[proj_id]
		if is_instance_valid(proj):
			proj.global_position = Vector2(projectile[2], projectile[3])
			server_projectiles[proj_id] = true
	for proj_id in client_player_projectiles.keys():
		if not server_projectiles.has(proj_id) and is_instance_valid(client_player_projectiles[proj_id]):
			client_player_projectiles[proj_id].queue_free()
			client_player_projectiles.erase(proj_id)

func spawn_projectile(position: Vector2, filepath: String):
	var projectile = load(filepath).instance()
	projectile.global_position = position
	$"/root/ClientMain/Projectiles".add_child(projectile)
	return projectile

func update_consumables(buffer: StreamPeerBuffer):
	var server_consumables = {}
	var num_consumables = buffer.get_u16()
	for _i in num_consumables:
		var consumable_id = buffer.get_32()
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		var filepath = buffer.get_string()
		if not client_consumables.has(consumable_id):
			client_consumables[consumable_id] = spawn_consumable(Vector2(pos_x, pos_y), filepath)
		var consumable = client_consumables[consumable_id]
		if is_instance_valid(consumable):
			consumable.global_position = Vector2(pos_x, pos_y)
			server_consumables[consumable_id] = true
	for consumable_id in client_consumables.keys():
		if not server_consumables.has(consumable_id) and is_instance_valid(client_consumables[consumable_id]):
			client_consumables[consumable_id].queue_free()
			client_consumables.erase(consumable_id)

func spawn_consumable(position: Vector2, filepath: String):
	var consumable = consumable_scene.instance()
	consumable.global_position = position
	consumable.call_deferred("set_texture", load(filepath))
	consumable.call_deferred("set_physics_process", false)
	$"/root/ClientMain/Consumables".add_child(consumable)
	return consumable

func update_neutrals(buffer: StreamPeerBuffer) -> void:
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
	for neutral_id in client_neutrals.keys():
		if not server_neutrals.has(neutral_id) and is_instance_valid(client_neutrals[neutral_id]):
			client_neutrals[neutral_id].queue_free()
			client_neutrals.erase(neutral_id)

func spawn_neutral(position: Vector2):
	var neutral = tree_scene.instance()
	neutral.global_position = position
	$"/root/ClientMain/Entities".add_child(neutral)
	return neutral

func update_structures(buffer: StreamPeerBuffer):
	var num_structures = buffer.get_u16()
	for _i in num_structures:
		var structure_id = buffer.get_32()
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		if not client_structures.has(structure_id):
			client_structures[structure_id] = spawn_structure(Vector2(pos_x, pos_y))

func spawn_structure(position: Vector2):
	var structure = load("res://entities/structures/turret/turret.tscn").instance()
	structure.global_position = position
	$"/root/ClientMain/Entities".add_child(structure)
	return structure

func update_enemy_projectiles(buffer: StreamPeerBuffer):
	var server_projectiles = {}
	var num_projectiles = buffer.get_u16()
	for _i in num_projectiles:
		var proj_id = buffer.get_32()
		var pos_x = buffer.get_float()
		var pos_y = buffer.get_float()
		var filepath = buffer.get_string()
		if not client_enemy_projectiles.has(proj_id):
			client_enemy_projectiles[proj_id] = spawn_projectile(Vector2(pos_x, pos_y), filepath)
		var proj = client_enemy_projectiles[proj_id]
		if is_instance_valid(proj):
			proj.global_position = Vector2(pos_x, pos_y)
			server_projectiles[proj_id] = true
	for proj_id in client_enemy_projectiles.keys():
		if not server_projectiles.has(proj_id) and is_instance_valid(client_enemy_projectiles[proj_id]):
			client_enemy_projectiles[proj_id].queue_free()
			client_enemy_projectiles.erase(proj_id)

func get_enemies_arrays(buffer: StreamPeerBuffer) -> Array:
	var enemies = []
	var num_enemies = buffer.get_u16()
	for _i in num_enemies:
		var enemy_data = []
		enemy_data.append(buffer.get_32()) # enemy_id
		enemy_data.append(buffer.get_string()) # filepath
		enemy_data.append(buffer.get_var()) # stats
		enemy_data.append(buffer.get_float()) # pos_x
		enemy_data.append(buffer.get_float()) # pos_y
		enemy_data.append(buffer.get_float()) # anim_x
		enemy_data.append(buffer.get_float()) # anim_y
		enemies.append(enemy_data)
	return [enemies]

func get_player_projectiles_array(buffer: StreamPeerBuffer) -> Array:
	var projectiles = []
	var num_projectiles = buffer.get_u16()
	for _i in num_projectiles:
		var proj_data = []
		proj_data.append(buffer.get_32()) # proj_id
		proj_data.append(buffer.get_string()) # filepath
		proj_data.append(buffer.get_float()) # pos_x
		proj_data.append(buffer.get_float()) # pos_y
		projectiles.append(proj_data)
	return projectiles

func get_batched_deaths(buffer: StreamPeerBuffer) -> Array:
	var deaths = []
	var num_deaths = buffer.get_u16()
	for _i in num_deaths:
		deaths.append(buffer.get_32())
	return deaths

func do_batched_deaths(deaths: Array):
	for enemy_id in deaths:
		if client_enemies.has(enemy_id) and is_instance_valid(client_enemies[enemy_id]):
			client_enemies[enemy_id].queue_free()
			client_enemies.erase(enemy_id)

func get_batched_damages(buffer: StreamPeerBuffer) -> Array:
	var damages = []
	var num_damages = buffer.get_u16()
	for _i in num_damages:
		var damage_data = []
		damage_data.append(buffer.get_32()) # enemy_id
		damage_data.append(buffer.get_32()) # damage
		damages.append(damage_data)
	return damages

func do_batched_damages(damages: Array):
	for damage_data in damages:
		var enemy_id = damage_data[0]
		var damage = damage_data[1]
		if client_enemies.has(enemy_id) and is_instance_valid(client_enemies[enemy_id]):
			client_enemies[enemy_id].take_damage(damage)

func get_batched_flashes(buffer: StreamPeerBuffer) -> Array:
	var flashes = []
	var num_flashes = buffer.get_u16()
	for _i in num_flashes:
		flashes.append(buffer.get_32())
	return flashes

func do_batched_flashes(flashes: Array):
	for enemy_id in flashes:
		if client_enemies.has(enemy_id) and is_instance_valid(client_enemies[enemy_id]):
			client_enemies[enemy_id].flash()

func get_batched_floating_text(buffer: StreamPeerBuffer) -> Array:
	var texts = []
	var num_texts = buffer.get_u16()
	for _i in num_texts:
		var text_data = {}
		text_data["position"] = Vector2(buffer.get_float(), buffer.get_float())
		text_data["value"] = buffer.get_string()
		texts.append(text_data)
	return texts

func do_batched_floating_text(texts: Array):
	var floating_text_manager = $"/root/ClientMain/FloatingTextManager"
	for text_data in texts:
		floating_text_manager.display(text_data["value"], text_data["position"], Color.white)

func get_batched_hit_effects(buffer: StreamPeerBuffer) -> Array:
	var effects = []
	var num_effects = buffer.get_u16()
	for _i in num_effects:
		var effect_data = {}
		effect_data["position"] = Vector2(buffer.get_float(), buffer.get_float())
		effect_data["filepath"] = buffer.get_string()
		effects.append(effect_data)
	return effects

func do_batched_hit_effects(effects: Array):
	for effect_data in effects:
		var effect = load(effect_data["filepath"]).instance()
		effect.global_position = effect_data["position"]
		$"/root/ClientMain/Effects".add_child(effect)
