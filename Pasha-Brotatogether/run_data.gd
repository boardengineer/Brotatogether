extends Node

func add_item(player_id: int, item:ItemData) -> void:
	var game_controller = get_game_controller()

	if not game_controller:
		return

	var run_data = game_controller.tracked_players[player_id]["run_data"]

	run_data["items"].push_back(item)
	apply_item_effects(player_id, item, run_data)
	add_item_displayed(player_id, item)
	update_item_related_effects(player_id)
	reset_linked_stats(player_id)

func add_weapon(player_id: int, weapon:WeaponData, is_starting:bool = false)->WeaponData:
	var game_controller = get_game_controller()

	if not game_controller:
		return null

	var run_data = game_controller.tracked_players[player_id]["run_data"]
	
	
	var new_weapon = weapon.duplicate()
	
	if is_starting:
		run_data["starting_weapon"] = weapon
	
	run_data.weapons.push_back(new_weapon)
	apply_item_effects(player_id, new_weapon, run_data)
	update_sets(player_id)
	update_item_related_effects(player_id)
	reset_linked_stats(player_id)
	
	return new_weapon


func add_starting_items_and_weapons(player_id:int) -> void:
	var game_controller = $"/root/GameController"

	var player = game_controller.tracked_players[player_id]
	var run_data = player.run_data
	
	if run_data.effects["starting_item"].size() > 0:
		for item_id in run_data.effects["starting_item"]:
			for i in item_id[1]:
				var item = ItemService.get_element(ItemService.items, item_id[0])
				add_item(player_id, item)
	
	if run_data.effects["starting_weapon"].size() > 0:
		for weapon_id in run_data.effects["starting_weapon"]:
			for i in weapon_id[1]:
				var weapon = ItemService.get_element(ItemService.weapons, weapon_id[0])
				var _weapon = add_weapon(player_id, weapon)

func add_character(player_id: int, character:CharacterData) -> void:
	var game_controller = get_game_controller()
	
	if not game_controller:
		return
		
	var run_data = game_controller.tracked_players[player_id]["run_data"]
	run_data["current_character"] = character
	add_item(player_id, character)

func apply_item_effects(player_id: int, item_data:ItemParentData, run_data) -> void:
	for effect in item_data.effects:
		effect.multiplayer_apply(run_data)

func update_sets(player_id: int) -> void:
	var game_controller = get_game_controller()
	
	if not game_controller:
		return
			
	var tracked_players = game_controller.tracked_players
	var run_data = tracked_players[player_id]["run_data"]
	
	for effect in run_data["active_set_effects"]:
		effect[1].multiplayer_unapply(player_id)
	
	run_data["active_set_effects"] = []
	run_data["active_sets"] = {}
	
	for weapon in run_data["weapons"]:
		for set in weapon.sets:
			if run_data["active_sets"].has(set.my_id):
				run_data["active_sets"][set.my_id] += 1
			else :
				run_data["active_sets"][set.my_id] = 1
	
	for key in run_data["active_sets"]:
		if run_data["active_sets"][key] >= 2:
			var set = ItemService.get_set(key)
			var set_effects = set.set_bonuses[min(run_data["active_sets"][key] - 2, set.set_bonuses.size() - 1)]
			
			for effect in set_effects:
				effect.multiplayer_apply(player_id)
				run_data["active_set_effects"].push_back([key, effect])

# Mirrors LinkedStats.reset()
# Zeroes out the stats in linked_stats and recalculates them based on effects
# with linked stats
func reset_linked_stats(player_id: int) -> void:
	var game_controller = get_game_controller()
	
	if not game_controller:
		return
	
	var tracked_players = game_controller.tracked_players
	var run_data = tracked_players[player_id]["run_data"]
	
	var linked_stats = RunData.init_stats(true)
	var update_on_gold_chance = false
	
	for linked_stat in run_data["effects"]["stat_links"]:
		var stat_to_tweak = linked_stat[0]
		var stat_scaled = 0
		
		if linked_stat[2] == "materials":
			stat_scaled = RunData.gold
			update_on_gold_chance = true
		elif linked_stat[2] == "structure":
			stat_scaled = RunData.effects["structures"].size()
		elif linked_stat[2] == "living_enemy":
			stat_scaled = RunData.current_living_enemies
		elif linked_stat[2] == "living_tree":
			stat_scaled = RunData.current_living_trees
		elif linked_stat[2] == "common_item":
			stat_scaled = RunData.get_nb_different_items_of_tier(Tier.COMMON)
		elif linked_stat[2] == "legendary_item":
			stat_scaled = RunData.get_nb_different_items_of_tier(Tier.LEGENDARY)
		elif linked_stat[2].begins_with("item_"):
			stat_scaled = RunData.get_nb_item(linked_stat[2], false)
		else :
			if RunData.effects.has(linked_stat[2]):
				if linked_stat[4] == true:
					stat_scaled = RunData.get_stat(linked_stat[2])
				else :
					stat_scaled = RunData.get_stat(linked_stat[2]) + TempStats.get_stat(linked_stat[2])
			else :
				continue
		
		var amount_to_add = linked_stat[1] * (stat_scaled / linked_stat[3])
		
		linked_stats[stat_to_tweak] = linked_stat[stat_to_tweak] + amount_to_add
	
	tracked_players[player_id]["linked_stats"]["update_on_gold_chance"]  = update_on_gold_chance
	tracked_players[player_id]["linked_stats"]["stats"] = linked_stats

func get_stat(player_id: int, stat_name:String) -> float:
	var game_controller = get_game_controller()
	
	if not game_controller:
		return 1.0
			
	var tracked_players = game_controller.tracked_players
	var run_data = tracked_players[player_id]["run_data"]
	
	return run_data["effects"][stat_name.to_lower()] * get_stat_gain(player_id, stat_name)


func get_stat_gain(player_id: int, stat_name:String)->float:
	var game_controller = get_game_controller()
	
	if not game_controller:
		return 1.0
			
	var tracked_players = game_controller.tracked_players
	var run_data = tracked_players[player_id]["run_data"]
	
	if not run_data["effects"].has("gain_" + stat_name.to_lower()):
		return 1.0
	
	return (1 + (run_data["effects"]["gain_" + stat_name.to_lower()] / 100.0))

func update_item_related_effects(player_id: int)->void :
	update_unique_bonuses(player_id)
	update_additional_weapon_bonuses(player_id)
	update_tier_iv_weapon_bonuses(player_id)
	update_tier_i_weapon_bonuses(player_id)

func update_tier_i_weapon_bonuses(player_id: int)->void :
	var game_controller = get_game_controller()
	
	if not game_controller:
		return
		
	var run_data = game_controller.tracked_players[player_id]["run_data"]
	
	for effect in run_data["tier_i_weapon_effects"]:
		run_data["effects"][effect[0]] -= effect[1]
	
	run_data["tier_i_weapon_effects"] = []
	
	for weapon in run_data["weapons"]:
		if weapon.tier <= Tier.COMMON:
			for effect in run_data["effects"]["tier_i_weapon_effects"]:
				run_data["effects"][effect[0]] += effect[1]
				run_data["tier_i_weapon_effects"].push_back(effect)

func update_tier_iv_weapon_bonuses(player_id: int) -> void:
	var game_controller = get_game_controller()
	
	if not game_controller:
		return
		
	var run_data = game_controller.tracked_players[player_id]["run_data"]
	
	for effect in run_data["tier_iv_weapon_effects"]:
		run_data["effects"][effect[0]] -= effect[1]
	
	run_data["tier_iv_weapon_effects"] = []
	
	for weapon in run_data["weapons"]:
		if weapon.tier >= Tier.LEGENDARY:
			for effect in run_data["effects"]["tier_iv_weapon_effects"]:
				run_data["effects"][effect[0]] += effect[1]
				run_data["tier_iv_weapon_effects"].push_back(effect)

func update_unique_bonuses(player_id: int) -> void:
	var game_controller = get_game_controller()
	
	if not game_controller:
		return
		
	var run_data = game_controller.tracked_players[player_id]["run_data"]
	var unique_effects = run_data["unique_effects"]
		
	for effect in unique_effects:
		run_data["effects"][effect[0]] -= effect[1]
	
	unique_effects = []
	var unique_weapon_ids = get_unique_weapon_ids(player_id)
	
	for i in unique_weapon_ids.size():
		for effect in run_data["effects"]["unique_weapon_effects"]:
			run_data["effects"][effect[0]] += effect[1]
			unique_effects.push_back(effect)

func get_unique_weapon_ids(player_id: int) -> Array:
	var game_controller = get_game_controller()
	
	if not game_controller:
		return []
		
	var run_data = game_controller.tracked_players[player_id]["run_data"]
	
	var unique_weapon_ids = []
	
	for weapon in run_data["weapons"]:
		if not unique_weapon_ids.has(weapon.weapon_id):
			unique_weapon_ids.push_back(weapon.weapon_id)
	
	return unique_weapon_ids

func update_additional_weapon_bonuses(player_id: int)->void :
	var game_controller = get_game_controller()
	
	if not game_controller:
		return

	var run_data = game_controller.tracked_players[player_id]["run_data"]
	
	for effect in run_data["additional_weapon_effects"]:
		run_data["effects"][effect[0]] -= effect[1]
	
	run_data["additional_weapon_effects"] = []
	
	for weapon in run_data["weapons"]:
		for effect in run_data["effects"]["additional_weapon_effects"]:
			run_data["effects"][effect[0]] += effect[1]
			run_data["additional_weapon_effects"].push_back(effect)

func add_item_displayed(player_id: int, new_item:ItemData) -> void:
	var game_controller = get_game_controller()
	
	if not game_controller:
		return
		
	var appearances_displayed = game_controller.tracked_players[player_id]["run_data"]["appearances_displayed"]
	
	for new_appearance in new_item.item_appearances:	
		if new_appearance == null:
			continue
		
		var display_appearance: = true
		
		if new_appearance.position != 0:
			var appearance_to_erase = null
			
			for appearance in appearances_displayed:
				if appearance.position != new_appearance.position or new_appearance.position == 0:
					continue
				
				if new_appearance.display_priority >= appearance.display_priority:
					appearance_to_erase = appearance
				else :
					display_appearance = false
				
				break
			
			if appearance_to_erase:
				appearances_displayed.erase(appearance_to_erase)
		
		if display_appearance:
			appearances_displayed.push_back(new_appearance)
		
	appearances_displayed.sort_custom(Sorter, "sort_depth_ascending")

func get_game_controller():
	if not $"/root".has_node("GameController"):
		return null
	return $"/root/GameController"
