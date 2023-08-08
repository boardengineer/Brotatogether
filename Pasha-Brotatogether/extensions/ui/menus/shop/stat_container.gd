extends StatContainer

func update_stat()->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"

		var player = game_controller.tracked_players[game_controller.self_peer_id]
		
		var utils = $"/root/MultiplayerUtils"
		
		var stat_value = utils.get_stat_multiplayer(game_controller.self_peer_id, key.to_lower())
		var value_text = str(stat_value as int)
	
		_icon.texture = ItemService.get_stat_small_icon(key.to_lower())
		_label.text = key
	
		if key.to_lower() == "stat_dodge" and stat_value > RunData.effects["dodge_cap"]:
			value_text += " | " + str(RunData.effects["dodge_cap"] as int)
		elif key.to_lower() == "stat_max_hp" and RunData.effects["hp_cap"] < 9999:
			value_text += " | " + str(RunData.effects["hp_cap"] as int)
		elif key.to_lower() == "stat_speed" and RunData.effects["speed_cap"] < 9999:
			value_text += " | " + str(RunData.effects["speed_cap"] as int)
		
		_value.text = value_text
	
		if stat_value > 0:
			_label.modulate = Color.green
			_value.modulate = Color.green
		elif stat_value < 0:
			_label.modulate = Color.red
			_value.modulate = Color.red
		else :
			_label.modulate = Color.white
			_value.modulate = Color.white
		
		print_debug("showing updated stat for ", key, " ", value_text)
#		.update_stat()
	else:
		.update_stat()
