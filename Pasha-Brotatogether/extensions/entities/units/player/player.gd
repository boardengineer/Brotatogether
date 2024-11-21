extends "res://entities/units/player/player.gd"

var player_network_id

var ClientMovementBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_movement_behavior.gd")

func add_weapon(weapon_data:WeaponData, pos:int)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.add_weapon(weapon_data, pos)
		return
		
	.add_weapon(weapon_data, pos)
	var weapon = current_weapons[current_weapons.size() - 1]
	
	var run_data_node = $"/root/MultiplayerRunData"
	var data_node = load("res://mods-unpacked/Pasha-Brotatogether/extensions/entities/units/player/weapon_data_node.gd").new()
	
	data_node.weapon_data = weapon_data
	data_node.weapon = weapon
	data_node.set_name("data_node")
	weapon.call_deferred("add_child", data_node)
	run_data_node.hitbox_to_owner_map[weapon._hitbox] = player_network_id
	for effect in weapon.effects:
		run_data_node.effect_to_owner_map[effect] = player_network_id


func remove_weapon_behaviors():
	_lose_health_timer.disconnect("timeout", self, "_on_LoseHealthTimer_timeout")
	
	for weapon in current_weapons:
		var shooting_behavior = weapon.get_node("ShootingBehavior")
		weapon.remove_child(shooting_behavior)
		var client_shooting_behavior = WeaponShootingBehavior.new()
		client_shooting_behavior.set_name("ShootingBehavior")
		weapon.add_child(client_shooting_behavior)
		weapon._shooting_behavior = client_shooting_behavior

func remove_movement_behavior():
	var movement_behavior_node = get_node("MovementBehavior")
	remove_child(movement_behavior_node)
	
	var client_behavior = ClientMovementBehavior.new()
	_movement_behavior = client_behavior
	_current_movement_behavior = client_behavior
	client_behavior.set_name("MovementBehavior")
	add_child(client_behavior)

func update_animation(movement:Vector2) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.update_animation(movement)
		return
		
	maybe_update_animation(movement, false)

func apply_items_effects() -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop() or player_network_id == null:
		.apply_items_effects()
		return
		
	var game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[player_network_id].run_data
	
	var animation_node = $Animation
	
	_hit_protection = run_data.effects["hit_protection"]
	
	if run_data.effects["alien_eyes"].size() > 0:
		_alien_eyes_timer = Timer.new()
		_alien_eyes_timer.wait_time = run_data.effects["alien_eyes"][0][3]
		var _alien_eyes = _alien_eyes_timer.connect("timeout", self, "on_alien_eyes_timeout")
		add_child(_alien_eyes_timer)
		_alien_eyes_timer.start()
		
	if run_data.effects["lose_hp_per_second"] > 0:
		_lose_health_timer.start()
	
	for i in run_data.weapons.size():
		add_weapon(run_data.weapons[i], i)
	
	var appearances_displayed = run_data.appearances_displayed
	appearances_displayed.sort_custom(Sorter, "sort_depth_ascending")
	var appearances_behind = []
		
	for appearance in appearances_displayed:
		var item_sprite = Sprite.new()
		item_sprite.texture = appearance.sprite
		animation_node.add_child(item_sprite)
		
		if appearance.depth < - 1:
			appearances_behind.push_back(item_sprite)
		
		_item_appearances.push_back(item_sprite)
	
	var popped = appearances_behind.pop_back()
	
	while popped != null:
		animation_node.move_child(popped, 0)
		popped = appearances_behind.pop_back()
	
	_sprites = animation_node.get_children()
	
	update_player_stats_multiplayer()
	current_stats.copy(max_stats)
	
	current_stats.health = max(1, max_stats.health * (run_data.effects["hp_start_wave"] / 100.0)) as int
	
	if run_data.effects["hp_start_next_wave"] != 100:
		current_stats.health = max(1, max_stats.health * (run_data.effects["hp_start_next_wave"] / 100.0)) as int
		run_data.effects["hp_start_next_wave"] = 100
	
	check_hp_regen()
	
	emit_signal("health_updated", current_stats.health, max_stats.health)


func update_player_stats_multiplayer()->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.update_player_stats()
		return
	
	var old_max_health = max_stats.health
	
	var game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[player_network_id]["run_data"]
	var multiplayer_utils = $"/root/MultiplayerUtils"
	var multiplayer_weapon_service = $"/root/MultiplayerWeaponService"
	
	max_stats.health = clamp(multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_max_hp"), 1, run_data.effects["hp_cap"]) as int
	max_stats.speed = stats.speed * (1 + (min(multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_speed"), run_data.effects["speed_cap"]) / 100.0)) as float
	max_stats.armor = multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_armor") as int
	max_stats.dodge = min(run_data.effects["dodge_cap"] / 100.0, multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_dodge") / 100.0)
#
#	print_debug("max health after (1.1)", max_stats.health)
#	print_debug("max health from utils", multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_max_hp"))
#
	
	if run_data.effects["explode_on_hit"].size() > 0:
#		init_exploding_stats()
		_explode_on_hit_stats = multiplayer_weapon_service.init_base_stats_multiplayer(player_network_id, run_data.effects["explode_on_hit"][0].stats, "", [], [ExplodingEffect.new()])
	
	current_stats.copy(max_stats, true)
	
	if old_max_health != max_stats.health:
		emit_signal("health_updated", current_stats.health, max_stats.health)
	
#	check_hp_regen()
#	func check_hp_regen()->void :

#	set_hp_regen_timer_value()
#	func set_hp_regen_timer_value()->void :
	_health_regen_timer.wait_time = RunData.get_hp_regeneration_timer(multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_hp_regeneration") as int)
	
	if run_data.effects["torture"] > 0:
		_health_regen_timer.wait_time = 1
		
	if (run_data.effects["torture"] > 0 or multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_hp_regeneration") > 0) and _health_regen_timer.is_stopped() and current_stats.health < max_stats.health and not cleaning_up:
		_health_regen_timer.start()

func maybe_update_animation(movement:Vector2, force_animation:bool)->void :
	if not is_instance_valid(self) or not is_inside_tree() or not is_instance_valid(_shadow):
		return
	var game_controller = $"/root/GameController"
	
	if force_animation or (game_controller.tracked_players.has(game_controller.self_peer_id) and game_controller.tracked_players[game_controller.self_peer_id].has("player") and game_controller.tracked_players[game_controller.self_peer_id]["player"] == self) or not game_controller.run_updates:
		pass
	else:
		return
	
	check_not_moving_stats(movement)
	check_moving_stats(movement)
	
	if movement.x > 0:
		_shadow.scale.x = abs(_shadow.scale.x)
		for sprite in $Animation.get_children():
			sprite.scale.x = abs(sprite.scale.x)
	elif movement.x < 0:
		_shadow.scale.x = - abs(_shadow.scale.x)
		for sprite in $Animation.get_children():
			sprite.scale.x = - abs(sprite.scale.x)

	if _animation_player.current_animation == "idle" and movement != Vector2.ZERO:
		_animation_player.play("move")
		_running_smoke.emit()
	elif _animation_player.current_animation == "move" and movement == Vector2.ZERO:
		_animation_player.play("idle")
		_running_smoke.stop()


func _on_ItemPickupArea_area_entered(area:Area2D) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		._on_ItemPickupArea_area_entered(area)
		return
		
	var game_controller = $"/root/GameController"
	if not game_controller.is_host:
		return
	
	get_tree().get_current_scene().emit_signal("picked_up_multiplayer", area, player_network_id)
	
	if consumables_in_range.has(area):
		consumables_in_range.erase(area)

func check_hp_regen() -> void:
	if not $"/root".has_node("GameController") or not player_network_id:
		.check_hp_regen()
		return
		
	var game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[player_network_id].run_data
	var multiplayer_utils = $"/root/MultiplayerUtils"
		
	set_hp_regen_timer_value()
	if (run_data.effects["torture"] > 0 or multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_hp_regeneration") > 0) and _health_regen_timer.is_stopped() and current_stats.health < max_stats.health and not cleaning_up:
		_health_regen_timer.start()


func set_hp_regen_timer_value()->void :
	if not $"/root".has_node("GameController") or not player_network_id:
		.set_hp_regen_timer_value()
		return

	var game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[player_network_id].run_data
	var multiplayer_utils = $"/root/MultiplayerUtils"
	_health_regen_timer.wait_time = RunData.get_hp_regeneration_timer(multiplayer_utils.get_stat_multiplayer(player_network_id,"stat_hp_regeneration") as int)
	
	if run_data.effects["torture"] > 0:
		_health_regen_timer.wait_time = 1

