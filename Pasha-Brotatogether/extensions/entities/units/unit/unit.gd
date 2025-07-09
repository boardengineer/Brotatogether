extends "res://entities/units/unit/unit.gd"

# THIS IS CURRENTLY A DUPE, hopefully that won't be a problem
enum EntityState {
	ENTITY_STATE_NETWORK_ID,
	
	ENTITY_STATE_X_POS,
	ENTITY_STATE_Y_POS,
	ENTITY_STATE_X_MOVE,
	ENTITY_STATE_Y_MOVE,
	ENTITY_STATE_CURRENT_HP,
	ENTITY_STATE_MAX_HP,
	ENTITY_STATE_SPRITE_SCALE,
	
	# Player-specific entity state.
	ENTITY_STATE_PLAYER_GOLD,
	ENTITY_STATE_PLAYER_CURRENT_XP,
	ENTITY_STATE_PLAYER_NEXT_LEVEL_XP,
	ENTITY_STATE_PLAYER_NUM_UPGRADES,
	ENTITY_STATE_PLAYER_WEAPONS,
	ENTITY_STATE_PLAYER_LEVEL,
}

enum WeaponState {
	WEAPON_STATE_X_POS,
	WEAPON_STATE_Y_POS,
	WEAPON_STATE_ROTATION,
	WEAPON_STATE_SPRITE_ROTATION,
	WEAPON_STATE_IS_SHOOTING,
}


func take_damage(value: int, args: TakeDamageArgs) -> Array:
	if self.in_multiplayer_game and not self.is_host:
		return []
	return .take_damage(value, args)


func _on_Hurtbox_area_entered(hitbox: Area2D) -> void :
	if self.in_multiplayer_game and not self.is_host:
		return
	._on_Hurtbox_area_entered(hitbox)


func flash()->void :
	if self.in_multiplayer_game and self.is_host:
		self.brotatogether_options.batched_unit_flashes[self.network_id] = true
	.flash()


func die(args: = Entity.DieArgs.new())->void :
	if self.in_multiplayer_game and self.is_host:
		self.brotatogether_options.batched_enemy_deaths[self.network_id] = true
	.die(args)


func update_client_enemy(unit_dict : Dictionary) -> void:
	set_deferred("position", Vector2(unit_dict["X_POS"], unit_dict["Y_POS"]))
	
	_current_movement.x = unit_dict["MOVE_X"]
	_current_movement.y = unit_dict["MOVE_Y"]
	
	var modulate_a = unit_dict["MODULATE_A"]
	var modulate_r = unit_dict["MODULATE_R"]
	var modulate_g = unit_dict["MODULATE_G"]
	var modulate_b = unit_dict["MODULATE_B"]
	
	sprite.self_modulate = Color8(modulate_r, modulate_g, modulate_b, modulate_a)
	
	call_deferred("update_animation", _current_movement)


func update_external_player_position(player_dict : Dictionary) -> void:
	self.position.x = player_dict[EntityState.ENTITY_STATE_X_POS]
	self.position.y = player_dict[EntityState.ENTITY_STATE_Y_POS]
		
	self.sprite.scale.x  = player_dict[EntityState.ENTITY_STATE_SPRITE_SCALE]
		
	self._current_movement.x  = player_dict[EntityState.ENTITY_STATE_X_MOVE]
	self._current_movement.y  = player_dict[EntityState.ENTITY_STATE_Y_MOVE]
		
	self.update_animation(_current_movement)


func update_client_player(player_dict : Dictionary, player_index : int) -> void:
	var current_xp = player_dict[EntityState.ENTITY_STATE_PLAYER_CURRENT_XP]
	var next_level_xp = player_dict[EntityState.ENTITY_STATE_PLAYER_NEXT_LEVEL_XP]
	RunData.players_data[player_index].current_xp = current_xp
	RunData.emit_signal("xp_added", current_xp, next_level_xp, player_index)
		
	var current_hp = player_dict[EntityState.ENTITY_STATE_CURRENT_HP]
	var max_hp = player_dict[EntityState.ENTITY_STATE_MAX_HP]
	var should_send_hp_signal = false
	if current_hp != self.current_stats.health:
		should_send_hp_signal = true
	self.current_stats.health = current_hp
	if max_hp != self.max_stats.health:
		should_send_hp_signal = true
	self.max_stats.health = max_hp
	if should_send_hp_signal:
		self.emit_signal("health_updated", self, self.current_stats.health, self.max_stats.health)
		
	var current_gold = player_dict[EntityState.ENTITY_STATE_PLAYER_GOLD]
	var current_level = player_dict[EntityState.ENTITY_STATE_PLAYER_LEVEL]
	RunData.players_data[player_index].gold = current_gold
	RunData.players_data[player_index].current_level = current_level
	
	RunData.emit_signal("gold_changed", current_gold, player_index)
		
	
		
	var weapons_array = player_dict[EntityState.ENTITY_STATE_PLAYER_WEAPONS]
	for weapon_index in weapons_array.size():
		var weapon_dict = weapons_array[weapon_index]
		var weapon = self.current_weapons[weapon_index]
		
		weapon.sprite.position.x = weapon_dict[WeaponState.WEAPON_STATE_X_POS]
		weapon.sprite.position.y = weapon_dict[WeaponState.WEAPON_STATE_Y_POS]
		weapon.sprite.rotation = weapon_dict[WeaponState.WEAPON_STATE_SPRITE_ROTATION]
		weapon.rotation = weapon_dict[WeaponState.WEAPON_STATE_ROTATION]
		weapon._is_shooting = weapon_dict[WeaponState.WEAPON_STATE_IS_SHOOTING]
		weapon._current_cooldown = 9999
