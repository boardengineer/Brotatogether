extends Node

const MIN_RANGE = 25
const DEFAULT_PROJECTILE_SCENE = preload("res://projectiles/bullet/bullet_projectile.tscn")

func init_melee_stats_multiplayer(player_id:int, from_stats:MeleeWeaponStats = MeleeWeaponStats.new(), weapon_id:String = "", sets:Array = [], effects:Array = [], is_structure:bool = false)->MeleeWeaponStats:
	var new_stats = init_base_stats_multiplayer(player_id, from_stats, weapon_id, sets, effects, is_structure) as MeleeWeaponStats
	
	var multiplayer_utils = $"/root/MultiplayerUtils"
	
	new_stats.alternate_attack_type = from_stats.alternate_attack_type
	
	if not is_structure:
		new_stats.max_range = max(MIN_RANGE, new_stats.max_range + (multiplayer_utils.get_stat_multiplayer(player_id, "stat_range") / 2.0)) as int
	
	return new_stats


func init_ranged_stats_multiplayer(player_id:int, from_stats:RangedWeaponStats = RangedWeaponStats.new(), weapon_id:String = "", sets:Array = [], effects:Array = [], is_structure:bool = false)->RangedWeaponStats:
	var new_stats = init_base_stats_multiplayer(player_id, from_stats, weapon_id, sets, effects, is_structure) as RangedWeaponStats
	
	var multiplayer_utils = $"/root/MultiplayerUtils"
	var game_controller = $"/root/GameController"

	var player = game_controller.tracked_players[player_id]
	var run_data = player.run_data
	
	if not is_structure:
		new_stats.max_range = max(MIN_RANGE, new_stats.max_range + multiplayer_utils.get_stat_multiplayer(player_id, "stat_range")) as int
	
	new_stats.projectile_spread = from_stats.projectile_spread + (run_data.effects["projectiles"] * 0.1)
	
	if from_stats.nb_projectiles > 0:
		new_stats.nb_projectiles = from_stats.nb_projectiles + run_data.effects["projectiles"]
	
	var piercing_dmg_bonus = (multiplayer_utils.get_stat_multiplayer(player_id, "piercing_damage") / 100.0)
	var bounce_dmg_bonus = (multiplayer_utils.get_stat_multiplayer(player_id, "bounce_damage") / 100.0)
	
	new_stats.piercing = from_stats.piercing + run_data.effects["piercing"]
	new_stats.piercing_dmg_reduction = clamp(from_stats.piercing_dmg_reduction - piercing_dmg_bonus, 0, 1)
	new_stats.bounce = from_stats.bounce + run_data.effects["bounce"]
	new_stats.bounce_dmg_reduction = clamp(from_stats.bounce_dmg_reduction - bounce_dmg_bonus, 0, 1)
	new_stats.projectile_scene = from_stats.projectile_scene
	
	if from_stats.increase_projectile_speed_with_range:
		new_stats.projectile_speed = clamp(from_stats.projectile_speed + (from_stats.projectile_speed / 300.0) * multiplayer_utils.get_stat_multiplayer(player_id, "stat_range"), 50, 6000) as int
	else :
		new_stats.projectile_speed = from_stats.projectile_speed
	
	return new_stats


func init_base_stats_multiplayer(player_id: int, from_stats:WeaponStats, weapon_id:String = "", sets:Array = [], effects:Array = [], is_structure:bool = false)->WeaponStats:
	var multiplayer_utils = $"/root/MultiplayerUtils"
	var game_controller = $"/root/GameController"

	var player = game_controller.tracked_players[player_id]
	var run_data = player.run_data
	
	var base_stats = from_stats.duplicate()
	var new_stats:WeaponStats
	var is_exploding = false
	
	if from_stats is MeleeWeaponStats:
		new_stats = MeleeWeaponStats.new()
	else :
		new_stats = RangedWeaponStats.new()
	
	for weapon_bonus in run_data.effects["weapon_bonus"]:
		if weapon_id == weapon_bonus[0]:
			base_stats.set(weapon_bonus[1], base_stats.get(weapon_bonus[1]) + weapon_bonus[2])
	
	for class_bonus in run_data.effects["weapon_class_bonus"]:
		for set in sets:
			if set.my_id == class_bonus[0]:
				var value = base_stats.get(class_bonus[1]) + class_bonus[2]
				
				if class_bonus[1] == "lifesteal":
					value = base_stats.get(class_bonus[1]) + (class_bonus[2] / 100.0)
				base_stats.set(class_bonus[1], value)
	
	for effect in effects:
		if effect is BurningEffect:
			base_stats.burning_data = BurningData.new(effect.burning_data.chance, effect.burning_data.damage, effect.burning_data.duration, 0)
		elif effect is WeaponStackEffect:
			var nb_same_weapon = 0
			
			for checked_weapon in run_data.weapons:
				if checked_weapon.weapon_id == effect.weapon_stacked_id:
					nb_same_weapon += 1
			
			base_stats.set(effect.stat_name, base_stats.get(effect.stat_name) + (effect.value * max(0.0, nb_same_weapon - 1)))
		elif effect is ExplodingEffect:
			is_exploding = true
	
	new_stats.scaling_stats = base_stats.scaling_stats
	
	var atk_spd = (multiplayer_utils.get_stat_multiplayer(player_id, "stat_attack_speed") + base_stats.attack_speed_mod) / 100.0
	
	if is_structure:
		atk_spd = 0
	
	new_stats.burning_data = init_burning_data_multiplayer(player_id, base_stats.burning_data, false, is_structure)
	new_stats.min_range = base_stats.min_range if not run_data.effects["no_min_range"] else 0
	new_stats.effect_scale = base_stats.effect_scale
	
	if atk_spd > 0:
		new_stats.cooldown = max(2, base_stats.cooldown * (1 / (1 + atk_spd))) as int
		new_stats.recoil = base_stats.recoil / (1 + atk_spd)
		new_stats.recoil_duration = base_stats.recoil_duration / (1 + atk_spd)
	else :
		new_stats.cooldown = max(2, base_stats.cooldown * (1 + abs(atk_spd))) as int
		new_stats.recoil = base_stats.recoil
		new_stats.recoil_duration = base_stats.recoil_duration
	
	new_stats.attack_speed_mod = base_stats.attack_speed_mod
	new_stats.max_range = base_stats.max_range
	
	if is_structure:
		new_stats.max_range = base_stats.max_range
	
	new_stats.damage = base_stats.damage
	new_stats.damage = max(1.0, new_stats.damage + get_scaling_stats_value_multiplayer(player_id, base_stats.scaling_stats)) as int
	
	var percent_dmg_bonus = (1 + (multiplayer_utils.get_stat_multiplayer(player_id, "stat_percent_damage") / 100.0))
	var exploding_dmg_bonus = 0
	
	if is_structure:
		percent_dmg_bonus = 1
	
	if is_exploding:
		exploding_dmg_bonus = (multiplayer_utils.get_stat_multiplayer(player_id, "explosion_damage") / 100.0)
	
	new_stats.damage = max(1, round(new_stats.damage * (percent_dmg_bonus + exploding_dmg_bonus))) as int
	
	new_stats.crit_damage = base_stats.crit_damage
	
	new_stats.crit_chance = base_stats.crit_chance + (multiplayer_utils.get_stat_multiplayer(player_id, "stat_crit_chance") / 100.0)
	
	if is_structure:
		new_stats.crit_chance = base_stats.crit_chance
	
	new_stats.accuracy = (base_stats.accuracy + (run_data.effects["accuracy"] / 100.0))
	new_stats.is_healing = base_stats.is_healing
	
	new_stats.lifesteal = ((multiplayer_utils.get_stat_multiplayer(player_id, "stat_lifesteal") / 100.0) + base_stats.lifesteal)
	
	if is_structure:
		new_stats.lifesteal = base_stats.lifesteal
	
	new_stats.knockback = max(0.0, base_stats.knockback + run_data.effects["knockback"]) as int
	
	new_stats.shooting_sounds = base_stats.shooting_sounds
	new_stats.sound_db_mod = base_stats.sound_db_mod
	new_stats.additional_cooldown_every_x_shots = base_stats.additional_cooldown_every_x_shots
	new_stats.additional_cooldown_multiplier = base_stats.additional_cooldown_multiplier
	
	return new_stats


func init_burning_data_multiplayer(player_id:int, base_burning_data:BurningData = BurningData.new(), is_global:bool = false, is_structure:bool = false)->BurningData:
	var multiplayer_utils = $"/root/MultiplayerUtils"
	
	var game_controller = $"/root/GameController"

	var player = game_controller.tracked_players[player_id]
	var run_data = player.run_data
	
	var new_burning_data = base_burning_data.duplicate()
	var global_burning = run_data.effects["burn_chance"]
	var base_weapon_has_no_burning = base_burning_data.chance == 0
	
	if not is_global:
		if base_burning_data.chance == 0:
			new_burning_data.chance = global_burning.chance
			new_burning_data.damage = global_burning.damage
			new_burning_data.duration = global_burning.duration
		elif base_burning_data.chance > 0:
			new_burning_data.damage += global_burning.damage
	
	new_burning_data.spread += run_data.effects["burning_spread"]
	
	if not is_structure or (is_structure and base_weapon_has_no_burning):
		
		new_burning_data.damage += multiplayer_utils.get_stat_multiplayer(player_id, "stat_elemental_damage")
		
		var percent_dmg_bonus = (1 + (multiplayer_utils.get_stat_multiplayer(player_id, "stat_percent_damage") / 100.0))
		new_burning_data.damage = max(1, round(new_burning_data.damage * percent_dmg_bonus)) as int
	
	return new_burning_data


func manage_special_spawn_projectile(
	entity_from:Unit, 
	p_weapon_stats:RangedWeaponStats, 
	auto_target_enemy:bool, 
	entity_spawner_ref:EntitySpawner, 
	p_direction:float = rand_range( - PI, PI), 
	damage_tracking_key:String = ""
)->Node:
	var pos = entity_from.global_position
	var weapon_stats = p_weapon_stats.duplicate()
	
	if weapon_stats.shooting_sounds.size() > 0:
		SoundManager2D.play(Utils.get_rand_element(weapon_stats.shooting_sounds), pos, 0, 0.2)
	
	var direction = p_direction
	
	if auto_target_enemy:
		var target = entity_spawner_ref.get_rand_enemy(entity_from)
		
		if target != null and is_instance_valid(target):
			direction = (target.global_position - pos).angle()
	
	var projectile = WeaponService.spawn_projectile(
		direction, 
		weapon_stats, 
		pos, 
		Vector2.ONE.rotated(direction), 
		true, 
		[], 
		null, 
		damage_tracking_key
	)
	
	return projectile


func spawn_projectile(
		rotation:float, 
		weapon_stats:RangedWeaponStats, 
		pos:Vector2, 
		knockback_direction:Vector2 = Vector2.ZERO, 
		deferred:bool = false, 
		effects:Array = [], 
		from:Node = null, 
		damage_tracking_key:String = ""
	)->Node:
	
	var projectile
	
	var duplicated_effects = []
	
	for effect in effects:
		duplicated_effects.push_back(effect.duplicate())
	
	if deferred:
		var main = get_tree().current_scene
		projectile = weapon_stats.projectile_scene.instance() if weapon_stats.projectile_scene != null else DEFAULT_PROJECTILE_SCENE.instance()
		main.call_deferred("add_child", projectile)
		projectile.set_deferred("global_position", pos)
		projectile.set_deferred("spawn_position", pos)
		projectile.set_deferred("velocity", Vector2.RIGHT.rotated(rotation) * weapon_stats.projectile_speed)
		projectile.set_deferred("rotation", (Vector2.RIGHT.rotated(rotation) * weapon_stats.projectile_speed).angle())
		projectile.set_deferred("weapon_stats", weapon_stats.duplicate())
		projectile.call_deferred("set_damage_tracking_key", damage_tracking_key)
		projectile.call_deferred("set_effects", duplicated_effects)
		projectile.call_deferred("set_from", from)
		projectile.call_deferred("set_damage", weapon_stats.damage, weapon_stats.accuracy, weapon_stats.crit_chance, weapon_stats.crit_damage, weapon_stats.burning_data, weapon_stats.is_healing)
		projectile.call_deferred("set_knockback_vector", knockback_direction, weapon_stats.knockback)
		projectile.call_deferred("set_effect_scale", weapon_stats.effect_scale)
	else :
		projectile = Utils.instance_scene_on_main(weapon_stats.projectile_scene if weapon_stats.projectile_scene != null else DEFAULT_PROJECTILE_SCENE, pos)
		projectile.spawn_position = pos
		projectile.set_effects(duplicated_effects)
		projectile.velocity = Vector2.RIGHT.rotated(rotation) * weapon_stats.projectile_speed
		projectile.rotation = projectile.velocity.angle()
		projectile.set_from(from)
		projectile.set_damage_tracking_key(damage_tracking_key)
		projectile.weapon_stats = weapon_stats.duplicate()
		projectile.set_damage(weapon_stats.damage, weapon_stats.accuracy, weapon_stats.crit_chance, weapon_stats.crit_damage, weapon_stats.burning_data, weapon_stats.is_healing)
		projectile.set_knockback_vector(knockback_direction, weapon_stats.knockback)
		projectile.set_effect_scale(weapon_stats.effect_scale)
	
	return projectile


func get_scaling_stats_icons(p_scaling_stats:Array)->String:
	
	var names = ""
	
	for i in p_scaling_stats.size():
		names += Utils.get_scaling_stat_text(p_scaling_stats[i][0], p_scaling_stats[i][1])
	
	return names


func get_scaling_stats_value_multiplayer(player_id:int, p_scaling_stats:Array)->float:
	var multiplayer_utils = $"/root/MultiplayerUtils"
	var game_controller = $"/root/GameController"
	var player = game_controller.tracked_players[player_id]
	var run_data = player.run_data
	
	var value = 0
	
	for scaling_stat in p_scaling_stats:
		if scaling_stat[0] == "stat_levels":
			value += run_data.current_level * scaling_stat[1]
		else :
			value += multiplayer_utils.get_stat_multiplayer(player_id, scaling_stat[0]) * scaling_stat[1]
	
	return value


func explode(effect:Effect, pos:Vector2, damage:int, accuracy:float, crit_chance:float, crit_dmg:float, burning_data:BurningData, is_healing:bool = false, ignored_objects:Array = [], damage_tracking_key:String = "")->Node:
	var main = get_tree().current_scene
	var instance = effect.explosion_scene.instance()
	instance.set_deferred("global_position", pos)
	main.call_deferred("add_child", instance)
	instance.set_deferred("sound_db_mod", effect.sound_db_mod)
	instance.call_deferred("set_damage_tracking_key", damage_tracking_key)
	instance.call_deferred("set_damage", damage, accuracy, crit_chance, crit_dmg, burning_data, is_healing, ignored_objects)
	instance.call_deferred("set_smoke_amount", round(effect.scale * effect.base_smoke_amount))
	instance.call_deferred("set_area", effect.scale)
	return instance
