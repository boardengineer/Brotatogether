extends "res://entities/units/unit/unit.gd"


func take_damage(value: int, args: TakeDamageArgs) -> Array:
	if self.in_multiplayer_game and not self.is_host:
		return []
	return .take_damage(value, args)


func _on_Hurtbox_area_entered(hitbox: Area2D) -> void :
	if self.in_multiplayer_game and not self.is_host:
		return
	._on_Hurtbox_area_entered(hitbox)
