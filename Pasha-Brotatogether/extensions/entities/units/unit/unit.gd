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
