extends "res://entities/structures/landmine/landmine.gd"


func _on_Area2D_body_exited(_body:Node)->void :
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		._on_Area2D_body_exited(_body)
		return

	if dead or effects.size() <= 0:return 

	var explosion_effect = effects[0]

	var multiplayer_weapon_service = $"/root/MultiplayerWeaponService"
	var player_id = get_node("StrcutureData").data["owner_player_id"]
	var _inst = multiplayer_weapon_service.explode_multiplayer(player_id, explosion_effect, global_position, stats.damage, stats.accuracy, stats.crit_chance, stats.crit_damage, stats.burning_data, false, [], explosion_effect.tracking_text)
	
	die()
