extends "res://ui/menus/shop/item_description.gd"

func set_item(item_data:ItemParentData) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.set_item(item_data)
		return
		
	var game_controller = $"/root/GameController"
	
	if not game_controller.tracked_players.has(game_controller.self_peer_id) or not game_controller.tracked_players[game_controller.self_peer_id].has("run_data"):
		.set_item(item_data)
		return
	
	get_effects().show()
	if item_data is WeaponData:
		get_weapon_stats().show()
		get_weapon_stats().bbcode_text = get_weapon_stats_text_for_weapon_data(game_controller.self_peer_id, item_data)
		_category.text = tr(ItemService.get_weapon_sets_text(item_data.sets))
	else :
		get_weapon_stats().hide()
		if item_data is CharacterData:
			_category.text = tr("CHARACTER")
		elif item_data is UpgradeData:
			_category.text = tr("UPGRADE")
		elif item_data is DifficultyData:
			_category.text = tr("DIFFICULTY")
		else :
			if item_data.max_nb == 1:
				_category.text = tr("UNIQUE")
			elif item_data.max_nb != - 1:
				_category.text = Text.text("LIMITED", [str(item_data.max_nb)])
			else :
				_category.text = tr("ITEM")
	
	if item_data is WeaponData or item_data is UpgradeData:
		var tier_number = ItemService.get_tier_number(item_data.tier)
		_name.text = tr(item_data.name) + (" " + tier_number if tier_number != "" else "")
	elif item_data is DifficultyData:
		_name.text = Text.text(tr(item_data.name), [str(item_data.value)])
	else :
		_name.text = item_data.name
	
	item = item_data
	_icon.texture = item_data.icon
	_name.modulate = ItemService.get_color_from_tier(item_data.tier)
	
	if item_data is DifficultyData and item_data.effects.size() == 0:
		get_effects().bbcode_text = item_data.description
	else :
		get_effects().bbcode_text = get_item_effects_text(item_data)

func get_weapon_stats_text_for_weapon_data(player_id:int, item_data:ItemParentData)->String:
	var current_stats
	
	var multiplayer_weapon_service = $"/root/MultiplayerWeaponService"
	
	if item_data.type == WeaponData.Type.MELEE:
		current_stats = multiplayer_weapon_service.init_melee_stats_multiplayer(player_id, item_data.stats, item_data.weapon_id, item_data.sets, item_data.effects)
	else :
		current_stats = multiplayer_weapon_service.init_ranged_stats_multiplayer(player_id, item_data.stats, item_data.weapon_id, item_data.sets, item_data.effects)
	
	return current_stats.get_text(item_data.stats)

func get_item_effects_text(item_data:ItemParentData) -> String:
	var text = ""
	
	for i in item_data.effects.size():
		var effect_text = item_data.effects[i].get_text()
		if item_data.effects[i] is GainStatForEveryStatEffect:
			effect_text = get_effect_text(item_data.effects[i])
		
		
		text += effect_text
		
		if effect_text != "" and i < item_data.effects.size() - 1:
				text += "\n"
	return text
	
func get_effect_text(effect:Effect, colored:bool = true) -> String:
	var key_text = effect.key.to_upper() if effect.text_key.length() == 0 else effect.text_key.to_upper()
	var args = get_effect_args(effect)
	var signs = []
	
	for i in args:
		signs.push_back(effect.get_sign(effect.effect_sign, effect.value))
	
	for custom_arg in effect.custom_args:
		var i = custom_arg.arg_index
		if i >= args.size():
			for j in (i - args.size()) + 1:
				args.push_back("")
				signs.push_back(Sign.NEUTRAL)
		
		args[i] = get_effect_arg_value(effect, custom_arg.arg_value, args[i])
		signs[i] = effect.get_sign(custom_arg.arg_sign, int(args[i]))
		args[i] = effect.get_formatted(custom_arg.arg_format, args[i], custom_arg.arg_value)
	
	return Text.text(key_text, args, [] if not colored else signs)

func get_effect_arg_value(effect:Effect, from_arg_value:int, p_base_value:String) -> String:
	var game_controller = $"/root/GameController"
	var multiplayer_utils = $"/root/MultiplayerUtils"
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
	
	var final_value = p_base_value
	
	if from_arg_value != ArgValue.USUAL:
		match from_arg_value:
			ArgValue.VALUE:final_value = str(effect.value)
			ArgValue.KEY:final_value = str(tr(effect.key.to_upper()))
			ArgValue.UNIQUE_WEAPONS:
				var nb = RunData.get_unique_weapon_ids().size()
				final_value = str(effect.value * nb)
			ArgValue.ADDITIONAL_WEAPONS:
				var nb = RunData.weapons.size()
				final_value = str(effect.value * nb)
			ArgValue.TIER:
				var val = "TIER_I"
				if effect.value == 1:val = "TIER_II"
				elif effect.value == 2:val = "TIER_III"
				elif effect.value == 3:val = "TIER_IV"
				final_value = tr(val)
			ArgValue.SCALING_STAT:
				final_value = Utils.get_scaling_stat_text(effect.key, effect.value / 100.0)
			ArgValue.SCALING_STAT_VALUE:
				final_value = str(multiplayer_utils.get_scaling_stats_value_multiplayer(game_controller.self_peer_id, [[effect.key, effect.value / 100.0]]))
			ArgValue.MAX_NB_OF_WAVES:
				final_value = str(RunData.nb_of_waves)
			ArgValue.TIER_IV_WEAPONS:
				var nb_tier_iv_weapons = 0
				for weapon in run_data.weapons:
					if weapon.tier >= Tier.LEGENDARY:
						nb_tier_iv_weapons += 1
				final_value = str(effect.value * nb_tier_iv_weapons)
			ArgValue.TIER_I_WEAPONS:
				var nb_tier_i_weapons = 0
				for weapon in run_data.weapons:
					if weapon.tier <= Tier.COMMON:
						nb_tier_i_weapons += 1
				final_value = str(effect.value * nb_tier_i_weapons)
			_:print("wrong value")
	return final_value

func get_effect_args(effect:Effect)->Array:
	var game_controller = $"/root/GameController"
	var multiplayer_utils = $"/root/MultiplayerUtils"
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
	var run_data_node = $"/root/MultiplayerRunData"

	var actual_nb_scaled = 0
	var key_arg = effect.key
	var perm_only = effect.text_key.to_upper() == "EFFECT_GAIN_STAT_FOR_EVERY_PERM_STAT"
	var stat_scaled = effect.stat_scaled
	
	if stat_scaled == "materials":
		actual_nb_scaled = run_data.gold
	elif stat_scaled == "structure":
		actual_nb_scaled = run_data.effects["structures"].size()
	elif stat_scaled == "living_enemy":
		actual_nb_scaled = RunData.current_living_enemies
	elif stat_scaled == "common_item":
		actual_nb_scaled = run_data_node.get_nb_different_items_of_tier(game_controller.self_peer_id, Tier.COMMON)
	elif stat_scaled == "legendary_item":
		actual_nb_scaled = run_data_node.get_nb_different_items_of_tier(game_controller.self_peer_id, Tier.LEGENDARY)
	elif stat_scaled.begins_with("item_"):
		actual_nb_scaled = run_data_node.get_nb_item(game_controller.self_peer_id, stat_scaled, false)
	elif stat_scaled == "living_tree":
		actual_nb_scaled = RunData.current_living_trees
	elif perm_only:
		actual_nb_scaled = run_data_node.get_stat(game_controller.self_peer_id, stat_scaled)
	else :
		actual_nb_scaled = run_data_node.get_stat(game_controller.self_peer_id, stat_scaled) + multiplayer_utils.get_temp_stat(game_controller.self_peer_id, stat_scaled)
	
	var bonus = floor(effect.value * (actual_nb_scaled / effect.nb_stat_scaled))
	
	if key_arg == "number_of_enemies":
		key_arg = "pct_number_of_enemies"
	
	return [str(effect.value), tr(key_arg.to_upper()), str(effect.nb_stat_scaled), tr(stat_scaled.to_upper()), str(bonus)]
