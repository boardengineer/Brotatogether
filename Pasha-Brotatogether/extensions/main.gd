#extends MainMenu
extends "res://main.gd"

signal levelled_up_multiplayer(player_id)
signal picked_up_multiplayer(item, player_id)

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
var health_tracker

func _ready():
	if not $"/root".has_node("GameController"):
		return
	
	game_controller = $"/root/GameController"
	if $"/root/GameController".is_coop():
		var run_data_node = $"/root/MultiplayerRunData"
		var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
		send_updates = true
		var _disconnect_error = RunData.disconnect("levelled_up", self, "on_levelled_up")
		var _connect_error = connect("levelled_up_multiplayer", self, "on_levelled_up_multiplayer")
		RunData.emit_signal("gold_changed", run_data.gold)
		
		if game_controller.is_host:
			spawn_additional_players()
			
		# connnect multiplayer signals
		_connect_error = connect("picked_up_multiplayer", self, "on_item_picked_up_multiplayer")
		run_data_node.reset_cache()
	
	game_controller.update_health(_player.current_stats.health, _player.max_stats.health)
	health_tracker = HealthTracker.instance()
	health_tracker.set_name("HealthTracker")
	$UI.add_child(health_tracker)
	health_tracker.init(game_controller.tracked_players)
	
func _on_EntitySpawner_player_spawned(player:Player)->void :
	if not $"/root".has_node("GameController"):
		._on_EntitySpawner_player_spawned(player)
		return
	
	var _error = player.connect("health_updated", self, "on_health_update")
	
	if not $"/root/GameController".is_coop():
		._on_EntitySpawner_player_spawned(player)
		return
	
	if not game_controller:
		game_controller = $"/root/GameController"
	
	_player = player
	TempStats.player = player
	_floating_text_manager.player = player
	
	player.get_remote_transform().remote_path = _camera.get_path()
	player.get_life_bar_remote_transform().remote_path = _player_life_bar_container.get_path()
	player.current_stats.health = max(1, player.max_stats.health * (RunData.effects["hp_start_wave"] / 100.0)) as int
	
	if RunData.effects["hp_start_next_wave"] != 100:
		player.current_stats.health = max(1, player.max_stats.health * (RunData.effects["hp_start_next_wave"] / 100.0)) as int
		on_player_health_updated(player.current_stats.health, player.max_stats.health)
		RunData.effects["hp_start_next_wave"] = 100
	
	player.check_hp_regen()
	_damage_vignette.update_from_hp(player.current_stats.health, player.max_stats.health)
	_life_bar.update_value(player.current_stats.health, player.max_stats.health)
	
	if ProgressData.settings.hp_bar_on_character:
		_player_life_bar.update_value(player.current_stats.health, player.max_stats.health)
	
	var _error_player_hp = player.connect("health_updated", self, "on_player_health_updated")
	set_life_label(player.current_stats.health, player.max_stats.health)
	_xp_bar.update_value(RunData.current_xp, RunData.get_next_level_xp_needed())
	var _error_hp_vignette = player.connect("health_updated", _damage_vignette, "update_from_hp")
	var _error_hp_lifebar = player.connect("health_updated", _life_bar, "update_value")
	var _error_hp_text = player.connect("healed", _floating_text_manager, "_on_player_healed")
	var _error_hp = player.connect("health_updated", self, "set_life_label")
	var _error_died = player.connect("died", self, "_on_player_died")
	var _error_took_damage = player.connect("took_damage", _screenshaker, "_on_player_took_damage")
	var _error_healing_effect = RunData.connect("healing_effect", player, "on_healing_effect")
	var _error_on_healed = player.connect("healed", self, "on_player_healed")
	var _error_lifesteal_effect = RunData.connect("lifesteal_effect", player, "on_lifesteal_effect")
	connect_visual_effects(player)
	
	for stat_next_wave in RunData.effects["stats_next_wave"]:
		TempStats.add_stat(stat_next_wave[0], stat_next_wave[1])
	
	RunData.effects["stats_next_wave"] = []
	
	check_half_health_stats(player.current_stats.health, player.max_stats.health)
	
	game_controller.update_health(player.current_stats.health, player.max_stats.health)
	set_life_label(player.current_stats.health, player.max_stats.health)
		
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
	var next_level_xp = RunData.get_xp_needed(run_data.current_level + 1)
	_xp_bar.update_value(run_data.current_xp, next_level_xp)

func _on_player_died(_p_player:Player) -> void:
	if $"/root".has_node("GameController"):
		$"/root/GameController".send_death()
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
			init_weapon_stats(weapon, game_controller.self_peer_id, true)
	
	if game_controller.is_source_of_truth:
		for player_id in game_controller.tracked_players: 
			if player_id == game_controller.self_peer_id:
				continue
				
			var spawn_pos = Vector2(spawn_x_pos, _entity_spawner._zone_max_pos.y / 2)
			var spawned_player = _entity_spawner.spawn_entity(player_scene, spawn_pos, true)
			spawned_player.player_network_id = player_id
			spawned_player.apply_items_effects()
			
			# re-init the weapons after we set the network id
			for weapon in spawned_player.current_weapons:
				if is_instance_valid(weapon):
					init_weapon_stats(weapon, player_id, true)
			
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
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.reload_stats()
		return
	
	var run_data_node = $"/root/MultiplayerRunData"		
	for player_id in game_controller.tracked_players:
		for weapon in game_controller.tracked_players[player_id].player.current_weapons:
			if is_instance_valid(weapon):
				init_weapon_stats(weapon, player_id, false)
			
		game_controller.tracked_players[player_id].player.update_player_stats_multiplayer()
		run_data_node.reset_linked_stats(player_id)
		
	for struct in _entity_spawner.structures:
		if is_instance_valid(struct):
			struct.reload_data()
	
	_proj_on_death_stat_cache.clear()

func init_weapon_stats(weapon:Weapon, player_id:int, at_wave_begin:bool = true) -> void:
	var multiplayer_weapon_service = $"/root/MultiplayerWeaponService"
	
	if weapon.stats is RangedWeaponStats:
		weapon.current_stats = multiplayer_weapon_service.init_ranged_stats_multiplayer(player_id, weapon.stats, weapon.weapon_id, weapon.weapon_sets, weapon.effects)
	else :
		weapon.current_stats = multiplayer_weapon_service.init_melee_stats_multiplayer(player_id, weapon.stats, weapon.weapon_id, weapon.weapon_sets, weapon.effects)
	
	weapon._hitbox.projectiles_on_hit = []
		
	for effect in weapon.effects:
		if effect is ProjectilesOnHitEffect:
			var weapon_stats = multiplayer_weapon_service.init_ranged_stats_multiplayer(player_id, effect.weapon_stats)
			weapon.set_projectile_on_hit(effect.value, weapon_stats, effect.auto_target_enemy)
	
	weapon.current_stats.burning_data = weapon.current_stats.burning_data.duplicate()
	weapon.current_stats.burning_data.from = weapon
	
	var current_stats = weapon.current_stats
	
	weapon._hitbox.effect_scale = weapon.current_stats.effect_scale
	weapon._hitbox.set_damage(current_stats.damage, current_stats.accuracy, current_stats.crit_chance, current_stats.crit_damage, current_stats.burning_data, current_stats.is_healing)
	weapon._hitbox.effects = weapon.effects
	weapon._hitbox.from = weapon
	
	if at_wave_begin:
		weapon._current_cooldown = current_stats.cooldown
		
		if weapon.effects.size() > 0:
			weapon._hitbox.disconnect("killed_something", weapon, "on_killed_something")
	
	weapon._range_shape.shape.radius = current_stats.max_range + 200

func _process(_delta):
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return
	
	game_controller = $"/root/GameController"
	if game_controller.is_host and send_updates:
		game_controller.send_game_state()

func send_player_position():
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return
	
	game_controller = $"/root/GameController"
	if get_tree().is_network_server():
		if not _end_wave_timer_timedout:
			game_controller.send_state()

func _on_WaveTimer_timeout() -> void:
	if health_tracker:
		health_tracker.hide()
	
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		._on_WaveTimer_timeout()
		return 
		
	game_controller = $"/root/GameController"
	if game_controller.is_host:
		send_updates = false
		game_controller.send_end_wave()
	
	._on_WaveTimer_timeout()
	
	var run_data_node = $"/root/MultiplayerRunData"
	for player_id in game_controller.tracked_players:
		var run_data = game_controller.tracked_players[player_id].run_data

		if run_data.effects["stats_end_of_wave"].size() > 0:
			for stat_end_of_wave in run_data.effects["stats_end_of_wave"]:
				run_data_node.add_stat(player_id, stat_end_of_wave[0], stat_end_of_wave[1])

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

func add_gold(player_id, value) -> void:
	var run_data = game_controller.tracked_players[player_id].run_data
	var linked_stats = game_controller.tracked_players[player_id].linked_stats
	var run_data_node = $"/root/MultiplayerRunData"
	
	run_data.gold += value
	
#	print_debug("adding gold for ", player_id, " to ", run_data.gold)
	if player_id == game_controller.self_peer_id:
		RunData.emit_signal("gold_changed", run_data.gold)
	
	if linked_stats.update_on_gold_chance:
		run_data_node.reset_linked_stats(player_id)
		
func add_xp(player_id, value) -> void:
	var run_data = game_controller.tracked_players[player_id].run_data
	var multiplayer_utils = $"/root/MultiplayerUtils"
	
	var xp_gained = value * (1 + multiplayer_utils.get_stat_multiplayer(player_id, "xp_gain") / 100)
	run_data.current_xp += xp_gained
	
	var next_level_xp = RunData.get_xp_needed(run_data.current_level + 1)
	if player_id == game_controller.self_peer_id:
		RunData.emit_signal("xp_added", run_data.current_xp, next_level_xp)
	
	while run_data.current_xp >= next_level_xp:

#		level_up
		run_data.current_xp = max(0, run_data.current_xp - RunData.get_xp_needed(run_data.current_level + 1))
		run_data.current_level += 1
		emit_signal("levelled_up_multiplayer", player_id)
		
		if player_id == game_controller.self_peer_id:
			RunData.emit_signal("xp_added", run_data.current_xp, next_level_xp)
		next_level_xp = RunData.get_xp_needed(run_data.current_level + 1)

func on_item_picked_up_multiplayer(item:Area2D, player_id:int) -> void:
	if item is Consumable:
		on_consumable_picked_up_multiplayer(item, player_id)
	else:
		_floating_text_manager.on_gold_picked_up(item)
		on_gold_picked_up_multiplayer(item,player_id)
	item.queue_free()

func on_gold_picked_up_multiplayer(gold:Node, player_id:int) -> void:
	_golds.erase(gold)
	
	if ProgressData.settings.alt_gold_sounds:
		SoundManager.play(Utils.get_rand_element(gold_alt_pickup_sounds), - 5, 0.2)
	else :
		SoundManager.play(Utils.get_rand_element(gold_pickup_sounds), 0, 0.2)
	
	var value = gold.value
	
	# The gold was picked up by the gold bag
	if player_id == -1:
		RunData.add_bonus_gold(value)
		return
	
	var run_data = game_controller.tracked_players[player_id].run_data
	
	if randf() < run_data.effects["chance_double_gold"] / 100.0:
		run_data.tracked_item_effects["item_metal_detector"] += value
		value *= 2
		gold.boosted *= 2
	
#	TODO cute monkey
	if randf() < run_data.effects["heal_when_pickup_gold"] / 100.0:
		var player = game_controller.tracked_players[player_id].player
		player.on_healing_effect(1, "item_cute_monkey")
	
	# NOTE: this is the only difference in this function, changing it from 
	# THE player to ANY player, in the future there may be separate inventories.
#	print_debug("A played picked up gold that player is ", gold.attracted_by.player_network_id)
		
	if run_data.effects["dmg_when_pickup_gold"].size() > 0:
		var dmg_taken = handle_stat_damages(run_data.effects["dmg_when_pickup_gold"])
		run_data.tracked_item_effects["item_baby_elephant"] += dmg_taken[1]
		
	add_gold(player_id, value)
	add_xp(player_id, value)

#	ProgressData.add_data("materials_collected")

func remove_gold(player_id, value:int) -> void:
	var run_data_node = $"/root/MultiplayerRunData"
			
	var tracked_players = game_controller.tracked_players
	var run_data = tracked_players[player_id]["run_data"]
	
	run_data["gold"] = max(0, run_data["gold"] - value) as int
	
#	TODO maybe we need signals
#	emit_signal("gold_changed", gold)

	if tracked_players[player_id]["linked_stats"]["update_on_gold_chance"]:
		run_data_node.reset_linked_stats(player_id)

func manage_harvesting() -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.manage_harvesting()
		return
	
	var multiplayer_utils = $"/root/MultiplayerUtils"
	
	for player_id in game_controller.tracked_players:
		var run_data = game_controller.tracked_players[player_id]["run_data"]
	
		var elite_end_wave_bonus = 0
		
		if multiplayer_utils.get_stat_multiplayer(player_id, "stat_harvesting") != 0 or run_data.effects["pacifist"] != 0 or elite_end_wave_bonus != 0 or _elite_killed_bonus != 0 or (run_data.effects["cryptid"] != 0 and RunData.current_living_trees != 0):
			var pacifist_bonus = round((_entity_spawner.get_all_enemies().size() + _entity_spawner.enemies_removed_for_perf) * (run_data.effects["pacifist"] / 100.0))
			var cryptid_bonus = RunData.current_living_trees * run_data.effects["cryptid"]
		
			if _is_horde_wave:
				pacifist_bonus = (pacifist_bonus / 2) as int
		
			var val = multiplayer_utils.get_stat_multiplayer(player_id, "stat_harvesting") + pacifist_bonus + cryptid_bonus + _elite_killed_bonus + elite_end_wave_bonus
		
#			TODO come back here
			add_gold(player_id, val)
			add_xp(player_id, val)
		
			_floating_text_manager.on_harvested(val)
		
			add_xp(player_id, 0)
	_harvesting_timer.start()

func _on_HarvestingTimer_timeout() -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		._on_HarvestingTimer_timeout()
		return

	var multiplayer_utils = $"/root/MultiplayerUtils"
	var run_data_node = $"/root/MultiplayerRunData"
	
	for player_id in game_controller.tracked_players:
		var run_data = game_controller.tracked_players[player_id].run_data
	
		if RunData.current_wave > RunData.nb_of_waves:
			var val = ceil(multiplayer_utils.get_stat_multiplayer(player_id, "stat_harvesting") * (RunData.ENDLESS_HARVESTING_DECREASE / 100.0))
			run_data_node.remove_stat(player_id, "stat_harvesting", val)
		else :
			var val = ceil(multiplayer_utils.get_stat_multiplayer(player_id, "stat_harvesting") * (run_data.effects["harvesting_growth"] / 100.0))
			
			if val > 0:
				run_data_node.add_stat(player_id, "stat_harvesting", val)

func remove_stat(player_id: int, stat_name:String, value:int)->void :
	var tracked_players = game_controller.tracked_players
	var run_data = tracked_players[player_id]["run_data"]
	
	run_data["effects"][stat_name] -= value


func set_level_label()->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.set_level_label()
		return
		
	game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
	
	_level_label.text = "LV." + str(run_data.current_level)

func on_levelled_up_multiplayer(player_id:int) -> void:
	var run_data = game_controller.tracked_players[player_id].run_data
	SoundManager.play(level_up_sound, 0, 0, true)
	var level = run_data.current_level
	
#	upgrades to process
	if player_id == game_controller.self_peer_id:
		emit_signal("upgrade_to_process_added", ItemService.upgrade_to_process_icon, level)
		_upgrades_to_process.push_back(level)
		_level_label.text = "LV." + str(level)
	else:
		game_controller.send_player_level_up(player_id, level)
	
	run_data.effects["stat_max_hp"] += 1
	reload_stats()
	
#	RunData.add_stat("stat_max_hp", 1)
	
	# TODO healing effect signal
	RunData.emit_signal("healing_effect", 1)
	
	for stat_level_up in run_data.effects["stats_on_level_up"]:
		run_data.effects[stat_level_up[0]] += stat_level_up[1]

func _on_EndWaveTimer_timeout() -> void:
	# Not only coop since both game types go to the multiplayer shop
	if not $"/root".has_node("GameController"):
		._on_EndWaveTimer_timeout()
		return
	
	if not game_controller:
		game_controller = $"/root/GameController"
	
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
		var consumables = _consumables_to_process
		if game_controller.is_coop():
			consumables = game_controller.tracked_players[game_controller.self_peer_id].consumables_to_process
		if consumables.size() > 0:
			for consumable in consumables:
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
		
		if game_controller.is_coop():
			game_controller.tracked_players[game_controller.self_peer_id].consumables_to_process = []
		
		var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/shop/multiplayer_shop.tscn")

func on_item_box_discard_button_pressed(item_data:ItemParentData) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.on_item_box_discard_button_pressed(item_data)
		return
		
	game_controller.discard_item_box(item_data)

func on_consumable_picked_up_multiplayer(consumable:Node, player_id:int)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.on_consumable_picked_up(consumable)
		return
	
	var run_data_node = $"/root/MultiplayerRunData"
	var run_data = game_controller.tracked_players[player_id].run_data
	
	RunData.consumables_picked_up_this_run += 1
	_consumables.erase(consumable)
	
	if (consumable.consumable_data.my_id == "consumable_item_box" or consumable.consumable_data.my_id == "consumable_legendary_item_box") and run_data.effects["item_box_gold"] != 0:
		run_data_node.add_gold(player_id, run_data.effects["item_box_gold"])
	
	if consumable.consumable_data.to_be_processed_at_end_of_wave:
		game_controller.on_consumable_to_process_added(player_id, consumable.consumable_data)
	
	if run_data.effects["consumable_stats_while_max"].size() > 0 and _player.current_stats.health >= _player.max_stats.health:
		for i in run_data.effects["consumable_stats_while_max"].size():
			var stat = run_data.effects["consumable_stats_while_max"][i]
			var has_max = (stat.size() > 2
				 and run_data.max_consumable_stats_gained_this_wave.size() > i
				 and run_data.max_consumable_stats_gained_this_wave[i].size() > 2)
			
			var reached_max = false
			
			if has_max:
				reached_max = run_data.max_consumable_stats_gained_this_wave[i][2] >= stat[2]
			
			if not has_max or not reached_max:
				run_data_node.add_stat(player_id, stat[0], stat[1])
								
				if has_max:
					run_data.max_consumable_stats_gained_this_wave[i][2] += stat[1]
	
	if not _cleaning_up:
		run_data_node.handle_explosion_multiplayer(player_id, "explode_on_consumable", consumable.global_position)
	
	run_data_node.apply_item_effects(player_id, consumable.consumable_data, run_data)

func on_item_box_take_button_pressed(item_data:ItemParentData)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.on_item_box_take_button_pressed(item_data)
		return
		
	game_controller.on_item_box_take_button_pressed(item_data)

func on_upgrade_selected(upgrade_data:UpgradeData)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.on_upgrade_selected(upgrade_data)
		return
		
	game_controller.on_upgrade_selected(upgrade_data)

func on_levelled_up() -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.on_levelled_up()
		return
	
	SoundManager.play(level_up_sound, 0, 0, true)
	var level = RunData.current_level
	emit_signal("upgrade_to_process_added", ItemService.upgrade_to_process_icon, level)
	_upgrades_to_process.push_back(level)
	set_level_label()
	RunData.add_stat("stat_max_hp", 1)
	RunData.emit_signal("healing_effect", 1)
	
	for stat_level_up in RunData.effects["stats_on_level_up"]:
		RunData.add_stat(stat_level_up[0], stat_level_up[1])
	
	game_controller = $"/root/GameController"
	if game_controller and game_controller.is_host:
		for player_id in game_controller.tracked_players:
			if player_id == game_controller.self_peer_id:
				continue
			if game_controller.tracked_players[player_id].has("player"):
				var player = game_controller.tracked_players[player_id]["player"]
				if player and is_instance_valid(player):
					player.max_stats.health += 1
					player.current_stats.health += 1
		game_controller.update_health(_player.current_stats.health, _player.max_stats.health)

func spawn_gold(unit:Unit, entity_type:int)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.spawn_gold(unit, entity_type)
		return
		
	var size_before = _golds.size()
	.spawn_gold(unit, entity_type)
	var size_after = _golds.size()
	
	var index = size_before
	while index < size_after:
		var gold = _golds[index]
		
		var _disconnect_error = gold.disconnect("picked_up", self, "on_gold_picked_up")
		_disconnect_error = gold.disconnect("picked_up", _floating_text_manager, "on_gold_picked_up")
		
		index += 1
		
		var instant_players = []
		
		for player_id in game_controller.tracked_players:
			var run_data = game_controller.tracked_players[player_id].run_data
			if randf() < (run_data.effects["instant_gold_attracting"] / 100.0):
				instant_players.push_back(game_controller.tracked_players[player_id].player)
		
		if instant_players.size() > 0:
			gold.attracted_by = Utils.get_rand_element(instant_players)

func spawn_consumables(unit:Unit) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.spawn_consumables(unit)
		return
	
	var size_before = _consumables.size()
	.spawn_consumables(unit)
	var size_after = _consumables.size()
	
	var index = size_before
	while index < size_after:
		var consumable = _consumables[index]
		
		var _connect_error = consumable.disconnect("picked_up", self, "on_consumable_picked_up")
		
		index += 1

func on_structure_wanted_to_spawn_fruit(pos:Vector2) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.on_structure_wanted_to_spawn_fruit(pos)
		return
	
	.on_structure_wanted_to_spawn_fruit(pos)
	
	var consumable = _consumables[_consumables.size() - 1]
	
	var _connect_error = consumable.disconnect("picked_up", self, "on_consumable_picked_up")

func _on_neutral_died(neutral:Neutral) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		._on_neutral_died(neutral)
		return
	
	var run_data_node = $"/root/MultiplayerRunData"
	
	._on_neutral_died(neutral)
	if not _cleaning_up:
		for player_id in game_controller.tracked_players:
			var run_data = game_controller.tracked_players[player_id].run_data
			
			if run_data.effects["tree_turrets"] > 0:
				for _i in run_data.effects["tree_turrets"]:
					var cloned_turret_effect = turret_effect.duplicate()
					run_data_node.effect_to_owner_map[cloned_turret_effect] = player_id
					var pos = _entity_spawner.get_spawn_pos_in_area(neutral.global_position, 200)
					_entity_spawner.queue_to_spawn_structures.push_back([EntityType.STRUCTURE, cloned_turret_effect.scene, pos, cloned_turret_effect])


func _on_enemy_died(enemy:Enemy) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		._on_enemy_died(enemy)
		return
		
	._on_enemy_died(enemy)
	
	var multiplayer_weapon_service = $"/root/MultiplayerWeaponService"
	var run_data_node = $"/root/MultiplayerRunData"
	
	if not _cleaning_up:
		for player_id in game_controller.tracked_players:
			var run_data = game_controller.tracked_players[player_id].run_data
			
			if run_data.effects["dmg_when_death"].size() > 0:
				var _dmg = handle_stat_damages(run_data.effects["dmg_when_death"])
			
			if run_data.effects["projectiles_on_death"].size() > 0:
				for proj_on_death_effect in run_data.effects["projectiles_on_death"]:
					for i in proj_on_death_effect[0]:
						var stats = proj_on_death_effect[1]
						
						if _proj_on_death_stat_cache.has(i):
							stats = _proj_on_death_stat_cache[i]
						else :
							stats = multiplayer_weapon_service.init_ranged_stats_multiplayer(player_id, proj_on_death_effect[1])
							_proj_on_death_stat_cache[i] = stats
						
						var _projectile = WeaponService.manage_special_spawn_projectile(
							enemy, 
							stats, 
							proj_on_death_effect[2], 
							_entity_spawner, 
							rand_range( - PI, PI), 
							"item_baby_with_a_beard"
						)
			
			run_data_node.handle_explosion_multiplayer(player_id, "explode_on_death", enemy.global_position)
