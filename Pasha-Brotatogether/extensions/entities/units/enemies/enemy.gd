extends "res://entities/units/enemies/enemy.gd"


func die(args: = Entity.DieArgs.new())->void :
	if self.in_multiplayer_game and self.is_host:
		self.brotatogether_options.batched_enemy_deaths[self.network_id] = true
	.die(args)


func _on_hurt(hitbox: Hitbox) -> void :
	if self.in_multiplayer_game and not self.is_host:
		return
	._on_hurt(hitbox)
