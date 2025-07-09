extends "res://entities/units/unit/unit.gd"


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
