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

#onready var game_controller = $"/root/GameController"

const NetworkedEnemy = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/entities/units/enemies/enemy.gd")
const HealthTracker = preload("res://mods-unpacked/Pasha-Brotatogether/ui/health_tracker/health_tracker.tscn")
const ClientMovementBehavior = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/entities/units/enemies/client_movement_behavior.gd")

var game_controller

func _ready():
	if not $"/root".has_node("GameController"):
		return
	game_controller = $"/root/GameController"
	
	if game_controller and game_controller.is_source_of_truth:
		spawn_additional_players()
	
	var health_tracker = HealthTracker.instance()
	health_tracker.set_name("HealthTracker")
	$UI.add_child(health_tracker)
	health_tracker.init(game_controller.tracked_players)
	
	print_debug("added health tracker")
	
	

func _on_EntitySpawner_player_spawned(player:Player)->void :
	._on_EntitySpawner_player_spawned(player)
	
	# This happens before ready()
	if not game_controller:
		if $"/root".has_node("GameController"):
			game_controller = $"/root/GameController"
			
	if game_controller:	
		game_controller.update_health(player.current_stats.health, player.max_stats.health)
		var _error = player.connect("health_updated", self, "on_health_update")

func _on_player_died(_p_player:Player)->void :
	if game_controller:
		game_controller.send_death()
	._on_player_died(_p_player)

func on_health_update(current_health:int, max_health:int) -> void:
	game_controller.update_health(current_health, max_health)

func spawn_additional_players() -> void:
	game_controller = $"/root/GameController"
	var spawn_x_pos = _entity_spawner._zone_max_pos.x / 2 + 200
	
	# The first player was created on at startup, create the rest manually
	game_controller.tracked_players[game_controller.self_peer_id]["player"] = _player
	if game_controller.is_source_of_truth:
		for player_id in game_controller.tracked_players: 
			if player_id == game_controller.self_peer_id:
				continue
				
			var spawn_pos = Vector2(spawn_x_pos, _entity_spawner._zone_max_pos.y / 2)
			var spawned_player = _entity_spawner.spawn_entity(player_scene, spawn_pos, true)
			
			connect_visual_effects(spawned_player)
			_clear_movement_behavior(spawned_player)
			
			if not game_controller.tracked_players.has(player_id):
				game_controller.tracked_players[player_id] = {}
			game_controller.tracked_players[player_id]["player"] = spawned_player
			spawn_x_pos += 200
	
func _process(_delta):
	if  $"/root".has_node("GameController"):
		game_controller = $"/root/GameController"
		if game_controller and game_controller.is_source_of_truth:
			game_controller.send_game_state()

func send_player_position():
	if  $"/root".has_node("GameController"):
		game_controller = $"/root/GameController"
		if get_tree().is_network_server():
			if not _end_wave_timer_timedout:
				game_controller.send_state()

func _on_WaveTimer_timeout()->void :
	if  $"/root".has_node("GameController"):
		game_controller = $"/root/GameController"
		if game_controller and game_controller.is_source_of_truth:
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

func on_gold_picked_up(gold:Node) -> void:
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

func _on_EndWaveTimer_timeout()->void :
	DebugService.log_data("_on_EndWaveTimer_timeout")
	_end_wave_timer_timedout = true
	_ui_dim_screen.dim()
	_ui_consumables_to_process.modulate = Color.white
	_ui_upgrades_to_process.modulate = Color.white
	_wave_cleared_label.hide()
	_wave_timer_label.hide()
	
	if _landmine_timer:
		_landmine_timer.stop()
	
	if _is_run_lost or is_last_wave() or _is_run_won:
		DebugService.log_data("end run...")
		RunData.run_won = not _is_run_lost
		
		if RunData.is_testing:
			var _error = get_tree().change_scene(MenuData.editor_scene)
		else :
			var _error = get_tree().change_scene("res://ui/menus/run/end_run.tscn")
	else :
		DebugService.log_data("process consumables and upgrades...")
		MusicManager.tween( - 8)
		if _consumables_to_process.size() > 0:
			for consumable in _consumables_to_process:
				var fixed_tier = - 1
				
				if consumable.my_id == "consumable_legendary_item_box":
					fixed_tier = Tier.LEGENDARY
				
				var item_data = ItemService.process_item_box(RunData.current_wave, consumable, fixed_tier)
				_item_box_ui.set_item_data(item_data)
				yield (_item_box_ui, "item_box_processed")
				_ui_consumables_to_process.remove_element(consumable)
		
		if _upgrades_to_process.size() > 0:
			for upgrade_to_process in _upgrades_to_process:
				_upgrades_ui.show_upgrade_options(upgrade_to_process)
				yield (_upgrades_ui, "upgrade_selected")
				_ui_upgrades_to_process.remove_element(upgrade_to_process)
		
		DebugService.log_data("display challenge ui...")
		if _is_chal_ui_displayed:
			yield (_challenge_completed_ui, "finished")
		
		if $"/root/GameController":
			var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/shop/multiplayer_shop.tscn")
		else:
			var _error = get_tree().change_scene("res://ui/menus/shop/shop.tscn")
