extends "res://entities/structures/turret/turret.gd"


func _on_AnimationPlayer_animation_finished(anim_name: String) -> void :
	if self.in_multiplayer_game and not self.is_host:
		return
	._on_AnimationPlayer_animation_finished(anim_name)

func shoot() -> void :
	if self.in_multiplayer_game and not self.is_host:
		return
	.shoot()
