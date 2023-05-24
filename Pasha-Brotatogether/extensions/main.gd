#extends MainMenu
extends "res://main.gd"

# must be g than 1024
var SERVER_PORT = 11111
var MAX_PLAYERS = 5
var SERVER_IP = "127.0.0.1"
const refresh_time = 1.0 / 100.0

var connected = false
var last_detailed_index = -1

var update_timer = refresh_time
var player_scene = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/entities/units/player/server_player.tscn")

onready var networking = $"/root/networking"

func _ready():
#	This is a good place to spawn a second player
	var spawn_x_pos = _entity_spawner._zone_max_pos.x / 2 + 200
	
	# The first player was created on at startup, create the rest manually
	networking.tracked_players[1] = {}
	networking.tracked_players[1]["player"] = _player
	if get_tree().is_network_server():
		for player_id in networking.client_players: 
			if player_id == 1:
				continue
				
			var spawn_pos = Vector2(spawn_x_pos, _entity_spawner._zone_max_pos.y / 2)
			var spawned_player = _entity_spawner.spawn_entity(player_scene, spawn_pos, true)
			
			connect_visual_effects(spawned_player)
			_clear_movement_behavior(spawned_player)
			
			networking.tracked_players[player_id] = {}
			networking.tracked_players[player_id]["player"] = spawned_player
			spawn_x_pos += 200
	
func _process(delta):
	send_player_position()

func send_player_position():
	if get_tree().is_network_server():
		var data = {}
		var position = _player.position
		var enemies = []
		var max_id = -1
		for enemy in _entity_spawner.enemies:
			if is_instance_valid(enemy):
				if enemy is NetworkedEnemy:
					var network_id = enemy.id
					var enemy_data = {}
					enemy_data["id"] = network_id
					
					# Details only needed on spawn, send sparingly
					if network_id > last_detailed_index:
						enemy_data["resource"] = enemy.stats.resource_path
						enemy_data["filename"] = enemy.filename
					
					if network_id > max_id:
						max_id = network_id
					enemy_data["position"] = enemy.position
					enemy_data["movement"] = enemy._current_movement
				
					enemies.push_back(enemy_data)
		data["enemies"] = enemies
		
		var births = []
		for birth in _entity_spawner.births:
			if is_instance_valid(birth):
				var birth_data = {}
				birth_data["position"] = birth.global_position
				birth_data["color"] = birth.color
				birth_data["id"] = birth.id
				births.push_back(birth_data)
#				print_debug("brith ", birth)
		data["births"] = births
				
		var items = []
		for item in _items_container.get_children():
			var item_data = {}
			
			item_data["id"]  = item.id
			item_data["scale_x"] = item.scale.x
			item_data["scale_y"] = item.scale.y
			item_data["position"] = item.global_position
			item_data["rotation"] = item.rotation
			item_data["push_back_destination"]  = item.push_back_destination
			
			# TODO we may want textures propagated
			items.push_back(item_data)
		data["items"] = items
					
		if max_id > last_detailed_index:
			last_detailed_index = max_id
		
		var players = []
		for player_id in networking.tracked_players:
			var player_data = {}
			var tracked_player = networking.tracked_players[player_id]["player"]
			player_data["id"] = player_id
			player_data["position"] = tracked_player.position
			player_data["speed"] = tracked_player.current_stats.speed
			player_data["movement"] = tracked_player._current_movement
			player_data["current_health"] = tracked_player.current_stats.health
			player_data["max_health"] = tracked_player.max_stats.health
			
			var weapons = []
			for weapon in tracked_player.current_weapons:
				var weapon_data = {}
				weapon_data["weapon_id"] = weapon.weapon_id
				weapon_data["position"] = weapon.sprite.position
				weapon_data["rotation"] = weapon.sprite.rotation
				
				if weapon.has_node("data_node"):
					var weapon_data_path = RunData.weapon_paths[weapon.get_node("data_node").weapon_data.my_id]
					weapon_data["data_path"] = weapon_data_path
#					print_debug("data_node ", data_resource_path)
				
				weapons.push_back(weapon_data)
			
			player_data["weapons"] = weapons
			players.push_back(player_data)
		data["players"] = players
		
		var projectiles = []
		var main = get_tree().current_scene
		for child in main.get_children():
			if child is PlayerProjectile:
				var projectile_data = {}
				projectile_data["id"] = child.id
				projectile_data["filename"] = child.filename
				projectile_data["position"] = child.position
				projectile_data["global_position"] = child.global_position
				projectile_data["rotation"] = child.rotation
				print_debug("sending projectile ", child.id)
				
				projectiles.push_back(projectile_data)
		data["projectiles"] = projectiles
		
		var consumables = []
		for consumable in main._consumables_container.get_children():
			var consumable_data = {}
			consumable_data["position"] = consumable.global_position
			consumable_data["id"] = consumable.id
			consumables.push_back(consumable_data)
		data["consumables"] = consumables
		
		var neutrals = []
		for neutral in _entity_spawner.neutrals:
			if is_instance_valid(neutral):
				var neutral_data = {}
				neutral_data["id"] = neutral.id
				neutral_data["position"] = neutral.global_position
				neutrals.push_back(neutral_data)
		data["neutrals"] = neutrals
			
		if not _end_wave_timer_timedout:
#			print_debug("sending ", data)
			$"/root/networking".rpc("update_player_position", data)

func _on_WaveTimer_timeout()->void :
	$"/root/networking".rpc("end_wave")
	._on_WaveTimer_timeout()

func _clear_movement_behavior(player:Player) -> void:
	# Players will only move via client calls, locally make them do
	# nothing
	# Since the player is added before it's children can be manipulatd,
	# manually set the current movement behavior to set it correctly
	var movement_behavior = player.get_node("MovementBehavior")
	player.remove_child(movement_behavior)
	var client_movement_behavior = ClientMovementBehavior.new()
	client_movement_behavior.set_name("MovementBehavior")
	player.add_child(client_movement_behavior)
	player._current_movement_behavior = client_movement_behavior
	
#	for weapon in player.current_weapons:
#		var shooting_behavior = weapon.get_node("ShootingBehavior")
#		weapon.remove_child(shooting_behavior)
#		var client_shooting_behavior = WeaponShootingBehavior.new()
#		client_shooting_behavior.set_name("ShootingBehavior")
#		weapon.add_child(client_shooting_behavior)
#		weapon._shooting_behavior = client_shooting_behavior
