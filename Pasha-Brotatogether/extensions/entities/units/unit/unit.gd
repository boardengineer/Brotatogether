extends "res://entities/units/unit/unit.gd"

func init(zone_min_pos:Vector2, zone_max_pos:Vector2, p_player_ref:Node2D = null, entity_spawner_ref:EntitySpawner = null) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.init(zone_min_pos, zone_max_pos, p_player_ref, entity_spawner_ref)
		return
	
	.init(zone_min_pos, zone_max_pos, p_player_ref, entity_spawner_ref)
	
	var game_controller = $"/root/GameController"
	var reduction_sum = 0
	
	for player_id in game_controller.tracked_players:
		var run_data = game_controller.tracked_players[player_id].run_data
		reduction_sum += run_data.effects["burning_cooldown_reduction"]
	
	_burning_timer.wait_time = max(0.1, _burning_timer.wait_time * (1.0 - (reduction_sum / 100.0)))

func take_damage(value:int, hitbox:Hitbox = null, dodgeable:bool = true, armor_applied:bool = true, custom_sound:Resource = null, base_effect_scale:float = 1.0)->Array:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return .take_damage(value, hitbox, dodgeable, armor_applied, custom_sound, base_effect_scale)
	
	var multiplayer_utils = $"/root/MultiplayerUtils"
	return multiplayer_utils.take_damage(self, value, hitbox, dodgeable, armor_applied, custom_sound, base_effect_scale)


func init_current_stats()->void :
	if not $"/root".has_node("GameController"):
		.init_current_stats()
		return
	
	var game_controller = $"/root/GameController"
	var multiplayer_utils = $"/root/MultiplayerUtils"
	
	max_stats.copy_stats(stats)
	var str_factor = Utils.get_stat("enemy_health") / 100.0
	if game_controller.is_coop():
		var sum := 0.0
		for player_id in game_controller.tracked_players:
			sum += multiplayer_utils.get_stat_multiplayer(player_id, "enemy_health")
		str_factor = sum / 100.0

	var accessibility_health_factor = RunData.current_run_accessibility_settings.health
	if game_controller.lobby_data.has("enemy_hp"):
		accessibility_health_factor = game_controller.lobby_data["enemy_hp"]
	
	var new_val = round((stats.health + (stats.health_increase_each_wave * (RunData.current_wave - 1))) * (accessibility_health_factor + str_factor))
	
	max_stats.health = round(new_val * (1.0 + RunData.get_endless_factor() * 2.25)) as int

	current_stats.copy(max_stats)
	reset_stats()


func _on_Hurtbox_area_entered(hitbox:Area2D)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		._on_Hurtbox_area_entered(hitbox)
		return

	if not hitbox.active or hitbox.ignored_objects.has(self):
		return 
		
	var run_data_node = $"/root/MultiplayerRunData"
	var multiplayer_weapon_service = $"/root/MultiplayerWeaponService"
		
	var dmg = hitbox.damage
	var dmg_taken = [0, 0]

	if hitbox.deals_damage:
		var is_exploding = false

		for effect in hitbox.effects:
			if effect is ExplodingEffect:
				if Utils.get_chance_success(effect.chance):
					var owner_player_id = run_data_node.hitbox_to_owner_map[hitbox]
					var explosion = multiplayer_weapon_service.explode_multiplayer(owner_player_id, effect, global_position, hitbox.damage, hitbox.accuracy, hitbox.crit_chance, hitbox.crit_damage, hitbox.burning_data, hitbox.is_healing)

					if hitbox.from != null and is_instance_valid(hitbox.from):
						explosion.connect("hit_something", hitbox.from, "on_weapon_hit_something")

					is_exploding = true

		
		if not is_exploding:
			dmg_taken = take_damage(dmg, hitbox)

			if hitbox.burning_data != null and Utils.get_chance_success(hitbox.burning_data.chance) and not hitbox.is_healing:
				apply_burning(hitbox.burning_data)

		if hitbox.projectiles_on_hit.size() > 0:
			for i in hitbox.projectiles_on_hit[0]:
				var projectile = WeaponService.manage_special_spawn_projectile(
					self, 
					hitbox.projectiles_on_hit[1], 
					hitbox.projectiles_on_hit[2], 
					_entity_spawner_ref
				)
				projectile.connect("hit_something", hitbox.from, "on_weapon_hit_something")

				projectile.call_deferred("set_ignored_objects", [self])

		on_hurt()

	hitbox.hit_something(self, dmg_taken[1])
