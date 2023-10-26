extends Node

func get_stat_multiplayer(player_id:int, stat_name:String) -> float:
	return $"/root/MultiplayerRunData".get_stat(player_id, stat_name) + get_temp_stat(player_id, stat_name) + get_linked_stats(player_id, stat_name)

func reset_temp_stats() -> void:
	var game_controller = get_game_controller()
	for player_id in game_controller.tracked_players:
		game_controller.tracked_players[player_id]["temp_stats"]["stats"] = RunData.init_stats()

func get_temp_stat(player_id:int, stat_name:String) -> float:
	var game_controller = get_game_controller()
	
	if not game_controller:
		return 0.0
	
	var tracked_players = game_controller.tracked_players
	
	if stat_name in tracked_players[player_id]["temp_stats"]["stats"]:
		return tracked_players[player_id]["temp_stats"]["stats"][stat_name] * $"/root/MultiplayerRunData".get_stat_gain(player_id, stat_name)
	else :
		return 0.0
		
		
func get_linked_stats(player_id:int, stat_name:String) -> float:
	var game_controller = get_game_controller()
	
	if not game_controller:
		return 0.0
	
	var tracked_players = game_controller.tracked_players
	
	if stat_name in tracked_players[player_id]["linked_stats"]["stats"]:
		return tracked_players[player_id]["linked_stats"]["stats"][stat_name] * $"/root/MultiplayerRunData".get_stat_gain(player_id, stat_name)
	else :
		return 0.0
	
func get_game_controller():
	if not $"/root".has_node("GameController"):
		return null
	return $"/root/GameController"

func take_damage(unit:Unit, value:int, hitbox:Hitbox = null, dodgeable:bool = true, armor_applied:bool = true, custom_sound:Resource = null, base_effect_scale:float = 1.0)->Array:
	if unit.dead:
		return [0, 0]
	
	var run_data_node = $"/root/MultiplayerRunData"
	var game_controller = $"/root/GameController"
	
	var crit_damage = 0.0
	var crit_chance = 0.0
	var knockback_direction = Vector2.ZERO
	var knockback_amount = 0.0
	var effect_scale = base_effect_scale
	var dmg_dealt = 0
	
	if hitbox != null:
		crit_damage = hitbox.crit_damage
		crit_chance = hitbox.crit_chance
		knockback_direction = hitbox.knockback_direction
		knockback_amount = hitbox.knockback_amount
		effect_scale = hitbox.effect_scale
	
	var is_crit = false
	var is_miss = false
	var is_dodge = false
	var is_protected = false
	var full_dmg_value = unit.get_dmg_value(value, armor_applied)
	var current_stats = unit.current_stats
	
	if dodgeable and randf() < min(current_stats.dodge, RunData.effects["dodge_cap"] / 100.0):
		full_dmg_value = 0
		is_dodge = true
	elif unit._hit_protection > 0:
		unit._hit_protection -= 1
		full_dmg_value = 0
		is_protected = true
	else :
		unit.flash()
	
	var sound = Utils.get_rand_element(unit.hurt_sounds)
	
	if full_dmg_value == 0:
		sound = Utils.get_rand_element(unit.dodge_sounds)
	elif not is_miss and randf() < crit_chance:
		
		full_dmg_value = unit.get_dmg_value(round(value * crit_damage) as int, true, true)
		
		dmg_dealt = clamp(full_dmg_value, 0, current_stats.health)
		
		if hitbox:
			hitbox.critically_hit_something(self, dmg_dealt)
		
		is_crit = true
		sound = Utils.get_rand_element(unit.crit_sounds)
	
	if custom_sound:
		sound = custom_sound
	
	SoundManager2D.play(sound, unit.global_position, 0, 0.2, unit.always_play_hurt_sound)
	
	dmg_dealt = clamp(full_dmg_value, 0, current_stats.health)
	current_stats.health = max(0.0, current_stats.health - full_dmg_value) as int
	
	unit._knockback_vector = knockback_direction * knockback_amount
	
	unit.emit_signal("health_updated", current_stats.health, unit.max_stats.health)
	
	var hit_type = HitType.NORMAL
	
	if current_stats.health <= 0:
		if hitbox:
			hitbox.killed_something(unit)
		unit.die(knockback_direction * max(knockback_amount, unit.MIN_DEATH_KNOCKBACK_AMOUNT))

	
		if hitbox:
			if run_data_node.hitbox_to_owner_map.has(hitbox):
				var player_id = run_data_node.hitbox_to_owner_map[hitbox]
				var run_data = game_controller.tracked_players[player_id].run_data
				var player = game_controller.tracked_players[player_id].player
		
				if is_crit:
					var gold_added = 0
					
					for effect in run_data.effects["gold_on_crit_kill"]:
						if randf() <= effect[1] / 100.0:
							gold_added += 1
			
					if run_data.effects["heal_on_crit_kill"] > 0:
						if randf() <= run_data.effects["heal_on_crit_kill"] / 100.0:
							player.on_healing_effect(1, "item_tentacle")
					
					for effect in hitbox.effects:
						if effect.key == "gold_on_crit_kill" and randf() <= effect.value / 100.0:
							gold_added += 1
							hitbox.added_gold_on_crit(gold_added)
					
					if gold_added > 0:
						run_data_node.add_gold(player_id, gold_added)
						hit_type = HitType.GOLD_ON_CRIT_KILL
	
	unit.emit_signal(
		"took_damage", 
		unit, 
		full_dmg_value, 
		knockback_direction, 
		knockback_amount, 
		is_crit, 
		is_miss, 
		is_dodge, 
		is_protected, 
		effect_scale, 
		hit_type
	)
	
	return [full_dmg_value, dmg_dealt, is_dodge]
