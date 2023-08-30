extends "res://singletons/item_service.gd"

func get_shop_items(wave:int, number:int = NB_SHOP_ITEMS, shop_items:Array = [], locked_items:Array = [])->Array:
	if not $"/root".has_node("GameController"):
		return .get_shop_items(wave, number, shop_items, locked_items)
		
	print_debug("getting shop items override")
	
	var game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
	
	var new_items = []
	var nb_weapons_guaranteed = 0
	var nb_weapons_added = 0
	var guaranteed_items:Array = run_data.effects["guaranteed_shop_items"].duplicate()
	
	var nb_locked_weapons = 0
	var _nb_locked_items = 0
	
	for locked_item in locked_items:
		if locked_item[0] is ItemData:
			_nb_locked_items += 1
		elif locked_item[0] is WeaponData:
			nb_locked_weapons += 1
	
	if RunData.current_wave < MAX_WAVE_TWO_WEAPONS_GUARANTEED:
		nb_weapons_guaranteed = 2
	elif RunData.current_wave < MAX_WAVE_ONE_WEAPON_GUARANTEED:
		nb_weapons_guaranteed = 1
	
	if run_data.effects["minimum_weapons_in_shop"] > nb_weapons_guaranteed:
		nb_weapons_guaranteed = run_data.effects["minimum_weapons_in_shop"]
	
	for i in number:
		
		var type
		
		if RunData.current_wave <= MAX_WAVE_TWO_WEAPONS_GUARANTEED:
			type = TierData.WEAPONS if (nb_weapons_added + nb_locked_weapons < nb_weapons_guaranteed) else TierData.ITEMS
		elif guaranteed_items.size() > 0:
			type = TierData.ITEMS
		else :
			type = TierData.WEAPONS if (randf() < CHANCE_WEAPON or nb_weapons_added + nb_locked_weapons < nb_weapons_guaranteed) else TierData.ITEMS
		
		if type == TierData.WEAPONS:
			nb_weapons_added += 1
		
		if run_data.effects["weapon_slot"] <= 0:
			type = TierData.ITEMS
		
		var new_item
		
		if type == TierData.ITEMS and guaranteed_items.size() > 0:
			new_item = get_element(items, guaranteed_items[0][0])
			guaranteed_items.pop_front()
		else :
			new_item = get_rand_item_from_wave(wave, type, new_items, shop_items)
		
		new_items.push_back([new_item, wave])
	
	return new_items

func get_recycling_value(wave:int, from_value:int, is_weapon:bool = false, affected_by_items_price_stat:bool = true)->int:
	if not $"/root".has_node("GameController"):
		return .get_recycling_value(wave, from_value, is_weapon, affected_by_items_price_stat)

	var game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data

	var actually_affected = affected_by_items_price_stat and RunData.current_wave <= RunData.nb_of_waves
	return max(1.0, (get_value(wave, from_value, actually_affected, is_weapon) * clamp((0.25 + (run_data.effects["recycling_gains"] / 100.0)), 0.01, 1.0))) as int


func get_value(wave:int, base_value:int, affected_by_items_price_stat:bool = true, is_weapon:bool = false, item_id:String = "") -> int:
	if not $"/root".has_node("GameController"):
		return .get_value(wave, base_value, affected_by_items_price_stat, is_weapon, item_id)
	
	var value_after_weapon_price = base_value if not is_weapon or not affected_by_items_price_stat else base_value * (1.0 + (RunData.effects["weapons_price"] / 100.0))
	
	var specific_item_price_factor = 0
	
	var game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
	
	for specific_item_price in run_data.effects["specific_items_price"]:
		if specific_item_price[0] == item_id:
			specific_item_price_factor = specific_item_price[1]
			break
			
	var items_price_factor = (1.0 + ((run_data.effects["items_price"] + specific_item_price_factor) / 100.0)) if affected_by_items_price_stat else 1.0
	var diff_factor = (run_data.effects["inflation"] / 100.0) if affected_by_items_price_stat else 0.0
	var endless_factor = (RunData.get_endless_factor(wave) / 5.0) if affected_by_items_price_stat else 0.0
	return max(1.0, ((value_after_weapon_price + wave + (value_after_weapon_price * wave * (0.1 + diff_factor))) * items_price_factor * (1 + endless_factor))) as int

func get_rand_item_from_wave(wave:int, type:int, shop_items:Array = [], prev_shop_items:Array = [], fixed_tier:int = - 1)->ItemParentData:
	if not $"/root".has_node("GameController"):
		return .get_rand_item_from_wave(wave, type, shop_items, prev_shop_items, fixed_tier)
	
	var game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[game_controller.self_peer_id].run_data
	
	var excluded_items = []
	excluded_items.append_array(shop_items)
	excluded_items.append_array(prev_shop_items)
	
	var rand_wanted = randf()
	var item_tier = get_tier_from_wave(wave)
	
	if fixed_tier != - 1:
		item_tier = fixed_tier
	
	if type == TierData.WEAPONS:
		item_tier = clamp(item_tier, run_data.effects["min_weapon_tier"], run_data.effects["max_weapon_tier"])
	
	var pool = get_pool(item_tier, type)
	var backup_pool = get_pool(item_tier, type)
	var items_to_remove = []
	
	for shop_item in excluded_items:
		pool.erase(shop_item[0])
		backup_pool.erase(shop_item[0])
	
	if type == TierData.WEAPONS:
		var bonus_chance_same_weapon_set = max(0, (MAX_WAVE_ONE_WEAPON_GUARANTEED + 1 - RunData.current_wave) * (BONUS_CHANCE_SAME_WEAPON_SET / MAX_WAVE_ONE_WEAPON_GUARANTEED))
		var chance_same_weapon_set = CHANCE_SAME_WEAPON_SET + bonus_chance_same_weapon_set

		
		if run_data.effects["no_melee_weapons"] > 0:
			for item in pool:
				if item.type == WeaponType.MELEE:
					backup_pool.erase(item)
					items_to_remove.push_back(item)
		
		if run_data.effects["no_ranged_weapons"] > 0:
			for item in pool:
				if item.type == WeaponType.RANGED:
					backup_pool.erase(item)
					items_to_remove.push_back(item)
		
		if run_data.weapons.size() > 0:
			if rand_wanted < CHANCE_SAME_WEAPON:

				var player_weapon_ids = []
				var nb_potential_same_weapons = 0
				
				for weapon in run_data.weapons:
					for item in pool:
						if item.weapon_id == weapon.weapon_id:
							nb_potential_same_weapons += 1
					player_weapon_ids.push_back(weapon.weapon_id)
				
				if nb_potential_same_weapons > 0:

					for item in pool:
						if not player_weapon_ids.has(item.weapon_id):

							items_to_remove.push_back(item)
				
			elif rand_wanted < chance_same_weapon_set:

				var player_sets = []
				var nb_potential_same_classes = 0
				
				for weapon in run_data.weapons:
					for set in weapon.sets:
						if not player_sets.has(set.my_id):
							player_sets.push_back(set.my_id)
				
				var weapons_to_potentially_remove = []
				
				for item in pool:
					var item_has_atleast_one_class = false
					for player_set_id in player_sets:
						for weapon_set in item.sets:
							if weapon_set.my_id == player_set_id:
	
								nb_potential_same_classes += 1
								item_has_atleast_one_class = true
								break
					
					if not item_has_atleast_one_class:
						weapons_to_potentially_remove.push_back(item)
				
				if nb_potential_same_classes > 0:

					for item in weapons_to_potentially_remove:
						items_to_remove.push_back(item)
	
	elif type == TierData.ITEMS and randf() < CHANCE_WANTED_ITEM_TAG and run_data.current_character.wanted_tags.size() > 0:
		for item in pool:
			var has_wanted_tag = false
			
			for tag in item.tags:
				if RunData.current_character.wanted_tags.has(tag):
					has_wanted_tag = true
					break
			
			if not has_wanted_tag:
				items_to_remove.push_back(item)
		

	
	var limited_items = {}
	
	for item in run_data.items:
		if item.max_nb == 1:
			backup_pool.erase(item)
			items_to_remove.push_back(item)
		elif item.max_nb != - 1:
			if limited_items.has(item.my_id):
				limited_items[item.my_id][1] += 1
			else :
				limited_items[item.my_id] = [item, 1]
	
	for key in limited_items:
		if limited_items[key][1] >= limited_items[key][0].max_nb:
			backup_pool.erase(limited_items[key][0])
			items_to_remove.push_back(limited_items[key][0])
	
	for item in items_to_remove:
		pool.erase(item)
	

	
	var elt
	
	if pool.size() == 0:
		if backup_pool.size() > 0:

			elt = Utils.get_rand_element(backup_pool)
		else :

			elt = Utils.get_rand_element(_tiers_data[item_tier][type])
	else :
		elt = Utils.get_rand_element(pool)
	
	return elt

func get_tier_from_wave(wave:int)->int:
	if not $"/root".has_node("GameController"):
		return .get_tier_from_wave(wave)
		
	var multiplayer_utils = $"/root/MultiplayerUtils"
	var game_controller = $"/root/GameController"
	
	var rand = rand_range(0.0, 1.0)
	var tier = Tier.COMMON
	var luck = multiplayer_utils.get_stat_multiplayer(game_controller.self_peer_id, "stat_luck") / 100.0
	
	for i in range(_tiers_data.size() - 1, - 1, - 1):
		var wave_base_chance = max(0.0, ((wave - 1) - _tiers_data[i][TierData.MIN_WAVE]) * _tiers_data[i][TierData.WAVE_BONUS_CHANCE])
		var wave_chance = 0.0
		
		if luck >= 0:
			wave_chance = wave_base_chance * (1 + luck)
		else :
			wave_chance = wave_base_chance / (1 + abs(luck))
		
		var chance = _tiers_data[i][TierData.BASE_CHANCE] + wave_chance
		var max_chance = _tiers_data[i][TierData.MAX_CHANCE]
		

		
		if rand <= min(chance, max_chance):
			tier = i
			break
	
	return tier
