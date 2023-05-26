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

onready var game_controller = $"/root/GameController"

const NetworkedEnemy = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/entities/units/enemies/enemy.gd")


func _ready():
#	This is a good place to spawn a second player
	var spawn_x_pos = _entity_spawner._zone_max_pos.x / 2 + 200
	
	# The first player was created on at startup, create the rest manually
	game_controller.tracked_players[game_controller.self_peer_id]["player"] = _player
	if game_controller.is_host:
		for player_id in game_controller.tracked_players: 
			if player_id == game_controller.self_peer_id:
				continue
				
			var spawn_pos = Vector2(spawn_x_pos, _entity_spawner._zone_max_pos.y / 2)
			var spawned_player = _entity_spawner.spawn_entity(player_scene, spawn_pos, true)
			
			connect_visual_effects(spawned_player)
			_clear_movement_behavior(spawned_player)
			
			game_controller.tracked_players[player_id] = {}
			game_controller.tracked_players[player_id]["player"] = spawned_player
			spawn_x_pos += 200
	
func _process(delta):
	if game_controller.is_host:
		game_controller.send_game_state()

func send_player_position():
	if get_tree().is_network_server():
		if not _end_wave_timer_timedout:
			game_controller.send_state()

func _on_WaveTimer_timeout()->void :
	game_controller.send_end_wave()
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

func on_gold_picked_up(gold:Node)->void :
	_golds.erase(gold)
	if ProgressData.settings.alt_gold_sounds:
		SoundManager.play(Utils.get_rand_element(gold_alt_pickup_sounds), - 5, 0.2)
	else :
		SoundManager.play(Utils.get_rand_element(gold_pickup_sounds), 0, 0.2)
	
	var value = gold.value
	
	if randf() < RunData.effects["chance_double_gold"] / 100.0:
		RunData.tracked_item_effects["item_metal_detector"] += value
		value *= 2
		gold.boosted *= 2
	
	if randf() < RunData.effects["heal_when_pickup_gold"] / 100.0:
		RunData.emit_signal("healing_effect", 1, "item_cute_monkey")
	
	# NOTE: this is the only difference in this function, changing it from 
	# THE player to ANY player, in the future there may be separate inventories.
	if gold.attracted_by is Player:
		
		if RunData.effects["dmg_when_pickup_gold"].size() > 0:
			var dmg_taken = handle_stat_damages(RunData.effects["dmg_when_pickup_gold"])
			RunData.tracked_item_effects["item_baby_elephant"] += dmg_taken[1]
		
		RunData.add_gold(value)
		RunData.add_xp(value)
		ProgressData.add_data("materials_collected")
	else :
		RunData.add_bonus_gold(value)
