extends RangedWeaponShootingBehavior

func shoot(_distance:float)->void :
	if get_tree().is_network_server():
		.shoot(_distance)
	
func shoot_projectile(rotation:float = _parent.rotation, knockback:Vector2 = Vector2.ZERO)->void :
	var is_client = not get_tree().is_network_server()
	if is_client:
		var networking = $"/root/networking"
		var main = get_tree().current_scene
		var player = networking.tracked_players[networking.self_peer_id]["player"]
		var shot_data = {}
		shot_data["rotation"] = rotation
		shot_data["knockback"] = knockback
		for weapon_index in player.current_weapons.size():
			var weapon = player.current_weapons[weapon_index]
			if weapon == _parent:
				shot_data["weapon_index"] = weapon_index
				break
		$"/root/networking".rpc("send_shot", shot_data)
	else:
		.shoot_projectile(rotation, knockback)
