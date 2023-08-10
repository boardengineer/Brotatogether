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

var NetworkedEnemy = load("res://mods-unpacked/Pasha-Brotatogether/extensions/entities/units/enemies/enemy.gd")
var HealthTracker = load("res://mods-unpacked/Pasha-Brotatogether/ui/health_tracker/health_tracker.tscn")
var ClientMovementBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_movement_behavior.gd")

var game_controller
var send_updates = true

func _ready():
	if not $"/root".has_node("GameController"):
		return
	game_controller = $"/root/GameController"
	send_updates = true
	
	if game_controller and game_controller.is_source_of_truth:
		spawn_additional_players()
		game_controller.update_health(_player.current_stats.health, _player.max_stats.health)
	
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
	_player.player_network_id = game_controller.self_peer_id
	_player.apply_items_effects()
	
	# re-init the weapons after we set the network id
	for weapon in _player.current_weapons:
		if is_instance_valid(weapon):
			init_weapon_stats(weapon, game_controller.self_peer_id, false)
	
	if game_controller.is_source_of_truth:
		for player_id in game_controller.tracked_players: 
			if player_id == game_controller.self_peer_id:
				continue
				
			var spawn_pos = Vector2(spawn_x_pos, _entity_spawner._zone_max_pos.y / 2)
			var spawned_player = _entity_spawner.spawn_entity(player_scene, spawn_pos, true)
			spawned_player.player_network_id = player_id
			spawned_player.apply_item_effects()
			
			# re-init the weapons after we set the network id
			for weapon in spawned_player.current_weapons:
				if is_instance_valid(weapon):
					init_weapon_stats(weapon, player_id, false)
			
			spawned_player.connect("health_updated", self, "on_health_update")
			spawned_player.connect("died", self, "_on_player_died")
			
			var _error_on_healed = spawned_player.connect("healed", self, "on_player_healed")
			
			spawned_player.dodge_sounds = _player.dodge_sounds.duplicate()
			
			connect_visual_effects(spawned_player)
			_clear_movement_behavior(spawned_player)
			
			if not game_controller.tracked_players.has(player_id):
				game_controller.tracked_players[player_id] = {}
			game_controller.tracked_players[player_id]["player"] = spawned_player
			spawn_x_pos += 200
	
func reload_stats()->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		var run_data_node = $"/root/MultiplayerRunData"
		
		for player_id in game_controller.tracked_players:
			for weapon in game_controller.tracked_players[player_id].player.current_weapons:
				if is_instance_valid(weapon):
					init_weapon_stats(weapon, player_id, false)
			
			print_debug("player_id ", player_id)
			
			game_controller.tracked_players[player_id].player.update_player_stats_multiplayer()
			run_data_node.reset_linked_stats(player_id)
		
		print_debug("multiplayer reload stats")
		
		for struct in _entity_spawner.structures:
			if is_instance_valid(struct):
				struct.reload_data()
	
		_proj_on_death_stat_cache.clear()
	else:
		.reload_stats()

func init_weapon_stats(weapon:Weapon, player_id:int, at_wave_begin:bool = true) -> void:
	print_debug("initting multiplayer weapon stats")
	
	var multiplayer_weapon_service = $"/root/MultiplayerWeaponService"
	
	if weapon.stats is RangedWeaponStats:
		weapon.current_stats = multiplayer_weapon_service.init_ranged_stats_multiplayer(player_id, weapon.stats, weapon.weapon_id, weapon.weapon_sets, weapon.effects)
	else :
		weapon.current_stats = multiplayer_weapon_service.init_melee_stats_multiplayer(player_id, weapon.stats, weapon.weapon_id, weapon.weapon_sets, weapon.effects)
	
	weapon._hitbox.projectiles_on_hit = []
		
	for effect in weapon.effects:
		if effect is ProjectilesOnHitEffect:
			var weapon_stats = multiplayer_weapon_service.init_ranged_stats_multiplayer(player_id, effect.weapon_stats)
			weapon.set_projectile_on_hit(effect.value, weapon.weapon_stats, effect.auto_target_enemy)
	
	weapon.current_stats.burning_data = weapon.current_stats.burning_data.duplicate()
	weapon.current_stats.burning_data.from = self
	
	var current_stats = weapon.current_stats
	
	weapon._hitbox.effect_scale = weapon.current_stats.effect_scale
	weapon._hitbox.set_damage(current_stats.damage, current_stats.accuracy, current_stats.crit_chance, current_stats.crit_damage, current_stats.burning_data, current_stats.is_healing)
	weapon._hitbox.effects = weapon.effects
	weapon._hitbox.from = self
	
	if at_wave_begin:
		weapon._current_cooldown = current_stats.cooldown
	
	weapon._range_shape.shape.radius = current_stats.max_range + 200

func _process(_delta):
	if  $"/root".has_node("GameController"):
		game_controller = $"/root/GameController"
		if game_controller and game_controller.is_source_of_truth and send_updates:
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
			send_updates = false
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

func on_consumable_picked_up(consumable:Node)->void :
	RunData.consumables_picked_up_this_run += 1
	_consumables.erase(consumable)
	
	if (consumable.consumable_data.my_id == "consumable_item_box" or consumable.consumable_data.my_id == "consumable_legendary_item_box") and RunData.effects["item_box_gold"] != 0:
		RunData.add_gold(RunData.effects["item_box_gold"])
		RunData.tracked_item_effects["item_bag"] += RunData.effects["item_box_gold"]
	
	if consumable.consumable_data.to_be_processed_at_end_of_wave:
		_consumables_to_process.push_back(consumable.consumable_data)
		emit_signal("consumable_to_process_added", consumable.consumable_data)
	
	if RunData.consumables_picked_up_this_run >= RunData.chal_hungry_value:
		ChallengeService.complete_challenge("chal_hungry")
	
	if RunData.effects["consumable_stats_while_max"].size() > 0 and _player.current_stats.health >= _player.max_stats.health:
		for i in RunData.effects["consumable_stats_while_max"].size():
			var stat = RunData.effects["consumable_stats_while_max"][i]
			var has_max = (stat.size() > 2
				 and RunData.max_consumable_stats_gained_this_wave.size() > i
				 and RunData.max_consumable_stats_gained_this_wave[i].size() > 2)
			
			var reached_max = false
			
			if has_max:
				reached_max = RunData.max_consumable_stats_gained_this_wave[i][2] >= stat[2]
			
			if not has_max or not reached_max:
				RunData.add_stat(stat[0], stat[1])
				
				if stat[0] == "stat_max_hp":
					RunData.tracked_item_effects["item_extra_stomach"] += stat[1]
				
				if has_max:
					RunData.max_consumable_stats_gained_this_wave[i][2] += stat[1]
	
	if not _cleaning_up:
		RunData.handle_explosion("explode_on_consumable", consumable.global_position)
	
	for effect in consumable.consumable_data.effects:
		if effect is HealingEffect:
			var player = consumable.attracted_by
			if player:
				player.on_healing_effect(max(1, effect.value + RunData.effects["consumable_heal"]), "")
		else:
			effect.apply()
	ChallengeService.check_stat_challenges()

func on_levelled_up()->void :
	SoundManager.play(level_up_sound, 0, 0, true)
	var level = RunData.current_level
	emit_signal("upgrade_to_process_added", ItemService.upgrade_to_process_icon, level)
	_upgrades_to_process.push_back(level)
	set_level_label()
	RunData.add_stat("stat_max_hp", 1)
	RunData.emit_signal("healing_effect", 1)
	
	for stat_level_up in RunData.effects["stats_on_level_up"]:
		RunData.add_stat(stat_level_up[0], stat_level_up[1])
	
	if  $"/root".has_node("GameController"):
		game_controller = $"/root/GameController"
		if game_controller and game_controller.is_source_of_truth:
			for player_id in game_controller.tracked_players:
				if player_id == game_controller.self_peer_id:
					continue
				if game_controller.tracked_players[player_id].has("player"):
					var player = game_controller.tracked_players[player_id]["player"]
					if player and is_instance_valid(player):
						player.max_stats.health += 1
						player.current_stats.health += 1
			game_controller.update_health(_player.current_stats.health, _player.max_stats.health)
