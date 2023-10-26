extends "res://projectiles/projectile.gd"

func set_to_be_destroyed() -> void:
	if not $"/root" or not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.set_to_be_destroyed()
		return
	
	var run_data_node = $"/root/MultiplayerRunData"
	
	if run_data_node.hitbox_to_owner_map.has(_hitbox):
		run_data_node.hitbox_to_owner_map.erase(_hitbox)
	
	to_be_destroyed = true
	_hitbox.active = false
	_hitbox.disable()
	queue_free()
