extends "res://weapons/melee/melee_weapon.gd"

func init_stats(at_wave_begin:bool = true) -> void:
	print_debug("(override) init weapon stats: ", _parent.player_network_id)
	
	if stats is RangedWeaponStats:
		current_stats = WeaponService.init_ranged_stats(stats, weapon_id, weapon_sets, effects)
	else :
		current_stats = WeaponService.init_melee_stats(stats, weapon_id, weapon_sets, effects)
	
	_hitbox.projectiles_on_hit = []
		
	for effect in effects:
		if effect is ProjectilesOnHitEffect:
			var weapon_stats = WeaponService.init_ranged_stats(effect.weapon_stats)
			set_projectile_on_hit(effect.value, weapon_stats, effect.auto_target_enemy)
	
	current_stats.burning_data = current_stats.burning_data.duplicate()
	current_stats.burning_data.from = self
	
	_hitbox.effect_scale = current_stats.effect_scale
	_hitbox.set_damage(current_stats.damage, current_stats.accuracy, current_stats.crit_chance, current_stats.crit_damage, current_stats.burning_data, current_stats.is_healing)
	_hitbox.effects = effects
	_hitbox.from = self
	
	if at_wave_begin:
		_current_cooldown = current_stats.cooldown
	
	_range_shape.shape.radius = current_stats.max_range + DETECTION_RANGE
