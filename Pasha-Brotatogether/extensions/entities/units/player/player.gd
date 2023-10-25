extends "res://entities/units/player/player.gd"

var player_network_id

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

func take_damage(value:int, hitbox:Hitbox = null, dodgeable:bool = true, armor_applied:bool = true, custom_sound:Resource = null, base_effect_scale:float = 1.0, bypass_invincibility:bool = false)->Array:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return .take_damage(value, hitbox, dodgeable, armor_applied, custom_sound, base_effect_scale, bypass_invincibility)
	
	var game_controller = $"/root/GameController"
	if not game_controller.is_host:
			return [0, 0 ,0]
			
	var run_data = game_controller.tracked_players[player_network_id].run_data
	var multiplayer_utils = $"/root/MultiplayerUtils"
	
	if hitbox and hitbox.is_healing:
		var _healed = on_healing_effect(value)
	elif _invincibility_timer.is_stopped() or bypass_invincibility:
		var dmg_taken = multiplayer_utils.take_damage(self, value, hitbox, dodgeable, armor_applied, custom_sound, base_effect_scale)
		
		if dmg_taken[2]:
			if run_data.effects["dmg_on_dodge"].size() > 0 and hitbox != null and hitbox.from != null and is_instance_valid(hitbox.from):
				var total_dmg_to_deal = 0
				for dmg_on_dodge in run_data.effects["dmg_on_dodge"]:
					if randf() >= dmg_on_dodge[2] / 100.0:
						continue
					var dmg_from_stat = max(1, (dmg_on_dodge[1] / 100.0) * Utils.get_stat(dmg_on_dodge[0]))
					var dmg = RunData.get_dmg(dmg_from_stat) as int
					total_dmg_to_deal += dmg
				var _dmg_dealt = hitbox.from.take_damage(total_dmg_to_deal)
			
			if run_data.effects["heal_on_dodge"].size() > 0:
				var total_to_heal = 0
				for heal_on_dodge in run_data.effects["heal_on_dodge"]:
					if randf() < heal_on_dodge[2] / 100.0:
						total_to_heal += heal_on_dodge[1]
				var _healed = on_healing_effect(total_to_heal, "item_adrenaline", false)
			
			if run_data.effects["temp_stats_on_dodge"].size() > 0:
				for temp_stat_on_hit in run_data.effects["temp_stats_on_dodge"]:
					game_controller.tracked_players[player_network_id]["temp_stats"]["stats"][temp_stat_on_hit[0]] += temp_stat_on_hit[1]
					TempStats.emit_signal("temp_stat_updated", temp_stat_on_hit[0], temp_stat_on_hit[1])
		
		if dmg_taken[1] > 0 and consumables_in_range.size() > 0:
			for cons in consumables_in_range:
				cons.attracted_by = self
		
		if dodgeable:
			disable_hurtbox()
			_invincibility_timer.start(get_iframes(dmg_taken[1]))
		
		if dmg_taken[1] > 0:
			if run_data.effects["explode_on_hit"].size() > 0:
				var effect = run_data.effects["explode_on_hit"][0]
				var stats = _explode_on_hit_stats
				var _inst = WeaponService.explode(effect, global_position, stats.damage, stats.accuracy, stats.crit_chance, stats.crit_damage, stats.burning_data)
			
			if run_data.effects["temp_stats_on_hit"].size() > 0:
				for temp_stat_on_hit in run_data.effects["temp_stats_on_hit"]:
					game_controller.tracked_players[player_network_id]["temp_stats"]["stats"][temp_stat_on_hit[0]] += temp_stat_on_hit[1]
					TempStats.emit_signal("temp_stat_updated", temp_stat_on_hit[0], temp_stat_on_hit[1])
			check_hp_regen()
		
		return dmg_taken
	
	return [0, 0]

func remove_weapon_behaviors():
	for weapon in current_weapons:
		var shooting_behavior = weapon.get_node("ShootingBehavior")
		weapon.remove_child(shooting_behavior)
		var client_shooting_behavior = WeaponShootingBehavior.new()
		client_shooting_behavior.set_name("ShootingBehavior")
		weapon.add_child(client_shooting_behavior)
		weapon._shooting_behavior = client_shooting_behavior
		
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
	
	RunData.sort_appearances()
	var appearances_behind = []
		
	for appearance in RunData.appearances_displayed:
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

func on_healing_effect_multiplayer(value:int, tracking_text:String = "", from_torture:bool = false)->int:
	
	var actual_value = min(value, max_stats.health - current_stats.health)
	var value_healed = heal(actual_value, from_torture)
	
	if value_healed > 0:
		SoundManager.play(Utils.get_rand_element(hp_regen_sounds), get_heal_db(), 0.1)
		emit_signal("health_updated", current_stats.health, max_stats.health)
		emit_signal("healed", self, actual_value)
		
		if tracking_text != "":
			RunData.tracked_item_effects[tracking_text] += value_healed
	
	return value_healed

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
		_explode_on_hit_stats = multiplayer_weapon_service.init_base_stats_multiplayer(run_data, run_data.effects["explode_on_hit"][0].stats, "", [], [ExplodingEffect.new()])
	
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
	
func _on_ItemAttractArea_area_entered(area:Area2D) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		._on_ItemAttractArea_area_entered(area)
		return
	
	var game_controller = $"/root/GameController"
	if game_controller.is_host:
			._on_ItemAttractArea_area_entered(area)
	

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

func on_alien_eyes_timeout() -> void:
	if not $"/root".has_node("GameController") or not player_network_id:
		.on_alien_eyes_timeout()
		return
	
	
	var game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[player_network_id].run_data
	var multiplayer_weapon_service = $"/root/MultiplayerWeaponService"
	
	var projectiles = []
	var alien_stats = multiplayer_weapon_service.init_ranged_stats_multiplayer(player_network_id, run_data.effects["alien_eyes"][0][1])
	
	SoundManager.play(Utils.get_rand_element(alien_sounds), 0, 0.1)
	
	for projectile in run_data.effects["alien_eyes"]:
		for i in projectile[0]:
			projectiles.push_back(projectile)
	
	for i in projectiles.size():
		var direction = (2 * PI / projectiles.size()) * i
		
		var _projectile = WeaponService.manage_special_spawn_projectile(
			self, 
			alien_stats, 
			projectiles[i][2], 
			_entity_spawner_ref, 
			direction, 
			"item_alien_eyes"
		)

func _on_LoseHealthTimer_timeout()->void :
	if not $"/root".has_node("GameController") or not player_network_id:
		.on_alien_eyes_timeout()
		return
		
	var game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[player_network_id].run_data
	
	var _dmg_taken = take_damage(run_data.effects["lose_hp_per_second"], null, false, false, null, 1.0, true)
