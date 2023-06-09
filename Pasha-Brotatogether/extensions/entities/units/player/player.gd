extends "res://entities/units/player/player.gd"

func add_weapon(weapon_data:WeaponData, pos:int)->void :
	.add_weapon(weapon_data, pos)
	var weapon = current_weapons[current_weapons.size() - 1]
	var data_node = load("res://mods-unpacked/Pasha-Brotatogether/extensions/entities/units/player/weapon_data_node.gd").new()
	data_node.weapon_data = weapon_data
	data_node.set_name("data_node")
	weapon.call_deferred("add_child", data_node)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass

func take_damage(value:int, hitbox:Hitbox = null, dodgeable:bool = true, armor_applied:bool = true, custom_sound:Resource = null, base_effect_scale:float = 1.0, bypass_invincibility:bool = false)->Array:
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
			return [0, 0 ,0]
	return .take_damage(value, hitbox, dodgeable, armor_applied, custom_sound, base_effect_scale, bypass_invincibility)

func remove_weapon_behaviors():
	for weapon in current_weapons:
		var shooting_behavior = weapon.get_node("ShootingBehavior")
		weapon.remove_child(shooting_behavior)
		var client_shooting_behavior = WeaponShootingBehavior.new()
		client_shooting_behavior.set_name("ShootingBehavior")
		weapon.add_child(client_shooting_behavior)
		weapon._shooting_behavior = client_shooting_behavior
		
		
func update_animation(movement:Vector2)->void :
	maybe_update_animation(movement, false)

func maybe_update_animation(movement:Vector2, force_animation:bool)->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if (not game_controller) or force_animation or game_controller.game_mode != "shared" or (game_controller.tracked_players.has(game_controller.self_peer_id) and game_controller.tracked_players[game_controller.self_peer_id].has("player") and game_controller.tracked_players[game_controller.self_peer_id]["player"] == self) or not game_controller.run_updates:
			pass
		else:
			return
	check_not_moving_stats(movement)
	check_moving_stats(movement)
	
	if movement.x > 0:
		_shadow.scale.x = abs(_shadow.scale.x)
		for sprite in $Animation.get_children():
			sprite.scale.x = abs(sprite.scale.x)
	elif movement.x < 0:
		_shadow.scale.x = - abs(_shadow.scale.x)
		for sprite in $Animation.get_children():
			sprite.scale.x = - abs(sprite.scale.x)

	if _animation_player.current_animation == "idle" and movement != Vector2.ZERO:
		_animation_player.play("move")
		_running_smoke.emit()
	elif _animation_player.current_animation == "move" and movement == Vector2.ZERO:
		_animation_player.play("idle")
		_running_smoke.stop()
	
func _on_ItemAttractArea_area_entered(area:Area2D)->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
			return
	._on_ItemAttractArea_area_entered(area)
