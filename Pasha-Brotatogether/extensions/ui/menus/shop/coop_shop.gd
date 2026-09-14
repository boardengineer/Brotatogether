extends "res://ui/menus/shop/coop_shop.gd"
const BT_VERBOSE := false   # per-shop BTSTATS stat dumps (two-machine debugging only)
const CarouselKeys = preload("res://mods-unpacked/Pasha-Brotatogether/ui/shop/carousel_keys.gd")

# Every stat key the shop stat panels display (stats_container.tscn exports, lowercased
# the way StatContainer hashes them). The HOST ships Utils.get_stat for each of these
# per player in the shop packet so clients can show true remote-player stats out of
# combat. String keys on the wire (self-documenting; gzip eats the repetition).
const SYNCED_STAT_KEYS = [
	"stat_max_hp", "stat_hp_regeneration", "stat_lifesteal", "stat_percent_damage",
	"stat_melee_damage", "stat_ranged_damage", "stat_elemental_damage",
	"stat_attack_speed", "stat_crit_chance", "stat_engineering", "stat_range",
	"stat_armor", "stat_dodge", "stat_speed", "stat_luck", "stat_harvesting",
	"consumable_heal", "burning_cooldown_reduction", "burning_spread", "bounce",
	"piercing", "piercing_damage", "damage_against_bosses", "pct_enemy_speed",
	"enemy_speed", "pct_number_of_enemies", "number_of_enemies", "enemy_damage",
	"explosion_size", "explosion_damage", "chance_double_gold", "chance_heal_on_gold",
	"heal_when_pickup_gold", "items_price", "item_box_gold", "free_rerolls",
	"xp_gain", "pickup_range", "knockback", "trees",
	"structure_attack_speed", "structure_range",
]


var steam_connection
var brotatogether_options


# The reroll button inits its tint from LOCAL gold before the host's post-harvest
# echo lands on clients, so it opened dark even when affordable. Re-tinted one frame
# after shop open (deferred from the ext _ready below) and on every shop packet.
func _bt_refresh_affordability_all() -> void:
	for pi in RunData.get_player_count():
		var rb = _get_reroll_button(pi)
		if rb != null and rb.has_method("set_color_from_currency"):
			rb.set_color_from_currency(RunData.get_player_gold(pi))
		var cont = _get_shop_items_container(pi)
		if cont != null:
			for shop_it in cont._shop_items:
				if shop_it != null and is_instance_valid(shop_it) and shop_it.has_method("update_color"):
					shop_it.update_color()



var in_multiplayer_game = false

# If true, the steam logic will be skipped to avoid duplicate rpc chains.
var is_self_call = false

var player_in_scene = [true, false, false, false]
var waiting_to_start_shop = false

var focusing_reroll_button = false
var focusing_go_button = false

# Force clients to update their focus, this syncs up focus after inventory
# changes (buys, discards, etc) and prevents the client focus from disappearing
var pending_force_focus = []


func _ready():
	steam_connection = $"/root/SteamConnection"

	brotatogether_options = $"/root/BrotogetherOptions"
	in_multiplayer_game = brotatogether_options.in_multiplayer_game

	if in_multiplayer_game:
		waiting_to_start_shop = true
		# Initial affordability tint (reroll button opened dark from stale local gold).
		call_deferred("_bt_refresh_affordability_all")
		# 9 / 0 page every player's carousel. This has to be a
		# last-added child: the FocusEmulators under this scene swallow the keys before this
		# script's own _input would ever see them (see ui/shop/carousel_keys.gd).
		var carousel_keys = CarouselKeys.new()
		carousel_keys.name = "BtCarouselKeys"
		carousel_keys.shop = self
		add_child(carousel_keys)

		steam_connection.connect("client_status_received", self, "_client_status_received")
		steam_connection.connect("shop_lobby_update", self, "_update_shop")
		steam_connection.connect("client_shop_focus_updated", self, "_client_shop_focus_updated")
		steam_connection.connect("client_shop_go_button_pressed", self, "_client_shop_go_button_pressed")
		steam_connection.connect("client_shop_discard_weapon", self, "_client_shop_discard_weapon")
		steam_connection.connect("client_shop_combine_weapon", self, "_client_shop_combine_weapon")
		steam_connection.connect("client_shop_buy_item", self, "_client_shop_buy_item")
		steam_connection.connect("client_shop_reroll", self, "_client_shop_reroll")
		steam_connection.connect("client_shop_lock_item", self, "_client_shop_lock_item")
		steam_connection.connect("client_shop_unlock_item", self, "_client_shop_unlock_item")
		steam_connection.connect("client_shop_focus_inventory_element", self, "_client_focused_inventory_element")
		steam_connection.connect("client_shop_requested", self, "send_shop_state")
		steam_connection.connect("close_popup", self, "_remote_close_client_popup")
		steam_connection.connect("receive_leave_shop", self, "_receive_leave_shop")
		steam_connection.connect("player_left_run", self, "_on_player_left_run")

		if steam_connection.is_host():
			steam_connection.send_host_entered_shop()


func _process(_delta):
	if in_multiplayer_game:
		if waiting_to_start_shop:
			if steam_connection.is_host():
				var all_players_entered = true
				for player_index in RunData.get_player_count():
					if not player_in_scene[player_index] and not steam_connection.left_players.has(player_index):
						all_players_entered = false
						break
				if all_players_entered:
					waiting_to_start_shop = false

					# Initial shop state, all players can break focus
					send_shop_state([0,1,2,3])
		_check_for_focus_change()


func _client_status_received(client_data : Dictionary, player_index : int) -> void:
	if waiting_to_start_shop:
		if client_data["CURRENT_SCENE"] == get_tree().current_scene.name:
			player_in_scene[player_index] = true


func _on_element_focused(element: InventoryElement, player_index: int)->void :
	._on_element_focused(element,player_index)

	if in_multiplayer_game:
		if is_self_call:
			is_self_call = false
		else:
			var focus_string = _dictionary_for_focus_inventory_element(element, player_index)
			steam_connection.shop_focus_inventory_element(focus_string)


func _client_shop_focus_updated(shop_item_string : String, player_index : int) -> void:
	is_self_call = true

	var shop_item : ShopItem = _shop_item_for_string(shop_item_string, player_index)
	if shop_item:
		Utils.get_focus_emulator(player_index).focused_control = shop_item._button


func _on_shop_item_focused(shop_item: ShopItem, player_index : int) -> void:
	if in_multiplayer_game:
		var is_me = player_index == steam_connection.get_my_index()
		if waiting_to_start_shop and not is_me:
			return
		._on_shop_item_focused(shop_item, player_index)
		if is_self_call:
			is_self_call = false
		elif is_me or steam_connection.is_host():
			var players_to_force = pending_force_focus.duplicate()
			pending_force_focus.clear()
			steam_connection.shop_item_focused(_string_for_shop_item(shop_item), players_to_force)
	else:
		._on_shop_item_focused(shop_item, player_index)


func _on_item_discard_button_pressed(weapon_data: WeaponData, player_index: int)->void :
	if in_multiplayer_game:
		if steam_connection.is_host():
			._on_item_discard_button_pressed(weapon_data, player_index)
			pending_force_focus.push_back(player_index)
		steam_connection.shop_weapon_discard(_string_for_weapon(weapon_data), player_index)
	else:
		._on_item_discard_button_pressed(weapon_data, player_index)


func _client_shop_discard_weapon(weapon_string : String, player_index : int) -> void:
	_on_item_discard_button_pressed(_weapon_for_string(weapon_string, player_index), player_index)
	steam_connection.request_close_client_shop_popup(player_index)


func _remote_close_client_popup() -> void:
	_get_coop_player_container(steam_connection.get_my_index()).item_popup.cancel()


func _on_GoButton_pressed(player_index: int) -> void:
	if in_multiplayer_game:
		if steam_connection.is_host():
			_on_go_button_pressed_brotatogether(player_index)
		steam_connection.shop_go_button_pressed(not _player_pressed_go_button[player_index])
	else:
		._on_GoButton_pressed(player_index)


func _on_go_button_pressed_brotatogether(player_index: int)->void :
	if get_tree().paused:
		return

	if _player_pressed_go_button[player_index]:
		_clear_go_button_pressed(player_index)
		return

	_player_pressed_go_button[player_index] = true
	var checkmark = _get_checkmark(player_index)
	if checkmark != null:
		checkmark.show()

	for other_player_index in RunData.get_player_count():
		if not _player_pressed_go_button[other_player_index] and not steam_connection.left_players.has(other_player_index):
			return

	RunData.current_wave += 1
	steam_connection.leave_shop()
	var _error = get_tree().change_scene(MenuData.game_scene)


func _receive_leave_shop() -> void:
	RunData.current_wave += 1
	var _error = get_tree().change_scene(MenuData.game_scene)


func _clear_go_button_pressed(player_index: int) -> void :
	if in_multiplayer_game:
		if steam_connection.is_host():
			._clear_go_button_pressed(player_index)
		steam_connection.shop_go_button_pressed(false)
	else:
		._clear_go_button_pressed(player_index)


func _client_shop_go_button_pressed(latest_go_state : bool, player_index : int) -> void:
	# Make the go function change the state to the new state by setting to the
	# opposite
	_player_pressed_go_button[player_index] = not latest_go_state
	_on_GoButton_pressed(player_index)


func on_shop_item_bought(shop_item: ShopItem, player_index: int) -> void:
	if in_multiplayer_game:
		if steam_connection.is_host():
			.on_shop_item_bought(shop_item, player_index)
			pending_force_focus.push_back(player_index)
		steam_connection.shop_buy_item(_string_for_shop_item(shop_item), player_index)
	else:
		.on_shop_item_bought(shop_item, player_index)


func _client_shop_buy_item(item_string : String, player_index : int) -> void:
	_get_shop_items_container(player_index).on_shop_item_buy_button_pressed(_shop_item_for_string(item_string, player_index))


func _on_item_combine_button_pressed(weapon_data: WeaponData, player_index: int)->void :
	if in_multiplayer_game:
		if steam_connection.is_host():
			pending_force_focus.push_back(player_index)
			._on_item_combine_button_pressed(weapon_data, player_index)
		steam_connection.shop_combine_weapon(_string_for_weapon(weapon_data), false, player_index)
	else:
		._on_item_combine_button_pressed(weapon_data, player_index)


func _client_shop_combine_weapon(weapon_string : String, _is_upgrade: bool, player_index : int) -> void:
	_on_item_combine_button_pressed(_weapon_for_string(weapon_string, player_index), player_index)
	steam_connection.request_close_client_shop_popup(player_index)


func _client_shop_lock_item(item_string : String, _wave_value: int, player_index: int) -> void:
	# A lock can race a reroll/shop-state echo: the named item may no longer exist on
	# this side (autoshop exposed it -- 36 Nil calls/run). Unresolvable = drop; the next
	# shop-state sync carries the authoritative lock set anyway.
	var locked_item = _shop_item_for_string(item_string, player_index)
	if locked_item != null:
		locked_item.change_lock_status(true)


func _client_shop_unlock_item(item_string : String, player_index : int) -> void:
	var unlocked_item = _shop_item_for_string(item_string, player_index)
	if unlocked_item != null:
		unlocked_item.change_lock_status(false)


func send_shop_state(changed_shop_player_indeces : Array = []) -> void:
	var result_dict : Dictionary = {}
	var abyssal_dlc = ProgressData.get_dlc_data("abyssal_terrors")

	var players_array = []
	var player_count: int = RunData.get_player_count()
	for player_index in player_count:
		var player_data = RunData.players_data[player_index]
		var player_dict = {}
		var shop_items = []
		for item in _shop_items[player_index]:
			var item_dict : Dictionary = {}

			item_dict["ID"] = item[0].my_id
			item_dict["WAVE_VALUE"] = item[1]

			if abyssal_dlc:
				if item[0].is_cursed:
					item_dict["CURSED"] = true

			shop_items.push_back(item_dict)
		player_dict["SHOP_ITEMS"] = shop_items

		player_dict["EFFECTS"] = player_data._serialize_effects(player_data.effects)
		var active_sets = {}
		for set in player_data.active_sets:
			active_sets[set] = player_data.active_sets[set]
		player_dict["ACTIVE_SETS"] = active_sets

		var locked_items : Array = []
		for item in RunData.locked_shop_items[player_index]:
			var item_dict : Dictionary = {}
			item_dict["ID"] = item[0].my_id
			item_dict["WAVE_VALUE"] = item[1]
			locked_items.push_back(item_dict)
		player_dict["LOCKED_ITEMS"] = locked_items

		var weapons_array = []
		for weapon in RunData.get_player_weapons(player_index):
			weapons_array.push_back(_dictionary_for_weapon(weapon))
		player_dict["WEAPONS"] = weapons_array
		player_dict["GO_PRESSED"] = _player_pressed_go_button[player_index]

		var gear_container : PlayerGearContainer = _get_gear_container(player_index)
		var items_array = []
		for element in gear_container.items_container._elements.get_children():
			items_array.push_back(_dictionary_for_inventory_item(element))
#			print_debug("shop container has ", element.item.my_id)
		player_dict["ITEMS"] = items_array

		player_dict["GOLD"] = RunData.get_player_gold(player_index)
		# XP and level ride ONLY the unreliable wave-end snapshot (main.gd:490-491, 471) and have no
		# other reliable correction -- unlike gold/effects/items, which this shop packet already
		# re-syncs. Include them so a dropped wave-end snapshot can't leave the client showing a
		# stale xp bar / level through the whole shop. (UNVALIDATED 2026-09-04.)
		player_dict["CURRENT_XP"] = RunData.players_data[player_index].current_xp
		player_dict["NEXT_LEVEL_XP"] = RunData.get_next_level_xp_needed(player_index)
		player_dict["CURRENT_LEVEL"] = RunData.players_data[player_index].current_level
		# Host-authoritative effective stats (base+temp+linked, i.e. what the host's own
		# panels show) so clients can display true stats for remote players out of combat.
		if steam_connection.is_host():
			var stats_dict = {}
			# A REMOTE player's effects dict can lack 3 DLC keys (chance_heal_on_gold,
			# pct_number_of_enemies, pct_enemy_speed -- per-slot init asymmetry), and
			# get_stat Nil-crashes on an absent key. Absent means default: send 0.
			var player_effects = RunData.get_player_effects(player_index)
			for stat_key in SYNCED_STAT_KEYS:
				var stat_hash = Keys.generate_hash(stat_key)
				stats_dict[stat_key] = Utils.get_stat(stat_hash, player_index) if player_effects.has(stat_hash) else 0.0
			player_dict["STATS"] = stats_dict
			if BT_VERBOSE:
				print("BTSTATS sent p%d max_hp=%d armor=%d luck=%d" % [player_index, stats_dict["stat_max_hp"], stats_dict["stat_armor"], stats_dict["stat_luck"]])
		player_dict["FOCUS"] = _focus_dictionary_for_player(player_index)

		player_dict["REROLL_PRICE"] = _reroll_price[player_index]
		player_dict["REROLL_DICSOUNT"] = _reroll_discount[player_index]
		player_dict["HAS_BONUS_FREE_REROLL"] = _has_bonus_free_reroll[player_index]


		players_array.push_back(player_dict)

	result_dict["PLAYERS"] = players_array
	result_dict["CHANGED_PLAYERS"] = changed_shop_player_indeces

#	print_debug("sending shop state with dict ", result_dict)
	steam_connection.send_shop_update(result_dict)


func _update_shop(shop_dictionary : Dictionary) -> void:
	if not shop_dictionary.has("PLAYERS"):
		print("WARNING - received shop update without PLAYERS element, ignoring; data:", shop_dictionary)
		return

	if steam_connection.is_host():
		print("WARNING - host shouldn't be updating for remote, returning; data:", shop_dictionary)
		return

#	print_debug("updating shop for dictionary - ", shop_dictionary)

	for player_index in shop_dictionary["PLAYERS"].size():
		var player_dict = shop_dictionary["PLAYERS"][player_index]

		var is_me = steam_connection.get_my_index() == player_index
		var can_update = not is_me or shop_dictionary["CHANGED_PLAYERS"].has(player_index)

		var go_pressed = player_dict["GO_PRESSED"]
		_player_pressed_go_button[player_index] = go_pressed
		var checkmark = _get_checkmark(player_index)
		if checkmark != null:
			if go_pressed:
				checkmark.show()
			else:
				checkmark.hide()

		if not can_update:
#			print_debug("skipping update for player ", player_index)
			continue

		Utils.get_focus_emulator(player_index)._clear_focused_control()
		_shop_items[player_index].clear()
		Utils.reset_stat_cache(player_index)
		var player_data = RunData.players_data[player_index]

		var reserilaized_effects = {}
		for key in player_dict["EFFECTS"]:
			reserilaized_effects[str(key)] = player_dict["EFFECTS"][key]
		player_data.effects = player_data._deserialize_effects(reserilaized_effects, {})

		player_data.active_sets.clear()
		var active_sets_dict = player_dict["ACTIVE_SETS"]
		for active_set in player_dict["ACTIVE_SETS"]:
			player_data.active_sets[active_set] = active_sets_dict[active_set]

		for shop_item_dict in player_dict["SHOP_ITEMS"]:
			_shop_items[player_index].push_back(_shop_item_for_dictionary(shop_item_dict))
		_get_shop_items_container(player_index).set_shop_items(_shop_items[player_index])

		var player_gear_container = _get_gear_container(player_index)

		RunData.players_data[player_index].weapons.clear()
		for weapon in player_dict["WEAPONS"]:
			RunData.players_data[player_index].weapons.push_back(_weapon_for_dictionary(weapon))
		player_gear_container.set_weapons_data(RunData.players_data[player_index].weapons)

		RunData.players_data[player_index].items.clear()
		for item in player_dict["ITEMS"]:
			for _i in item["NUMBER"]:
				RunData.players_data[player_index].items.push_back(_inventory_item_for_dictionary(item))
		player_gear_container.set_items_data(RunData.players_data[player_index].items)


		if player_dict.has("FOCUS"):
			_set_client_focus_for_player(player_dict["FOCUS"], player_index)
		else:
			print_debug("WARN - missing focus for player ", player_index, " ", player_dict)

		_reroll_price[player_index] = player_dict["REROLL_PRICE"]
		_reroll_discount[player_index] = player_dict["REROLL_DICSOUNT"]
		_has_bonus_free_reroll[player_index] = player_dict["HAS_BONUS_FREE_REROLL"]
		set_reroll_button_price(player_index)

		var locked_items : Array = player_dict["LOCKED_ITEMS"]
		for item in _get_shop_items_container(player_index).get_children():
			if not item is ShopItem:
				continue

			var is_locked = false
			for locked_item in locked_items:
				if locked_item["ID"] == item.item_data.my_id:
					is_locked = true
					break

			if is_locked:
				item.lock_visually()
			else:
				item.unlock_visually()

		RunData.players_data[player_index].gold = player_dict["GOLD"]
		_get_gold_label(player_index).update_value(RunData.players_data[player_index].gold)
		# Direct gold assignment skips gold_changed AND the local spend paths that
		# normally re-tint affordability, so the reroll button stayed dark (and shop
		# item prices mis-tinted) after the host echoed gold back. Refresh both.
		var reroll_btn = _get_reroll_button(player_index)
		if reroll_btn != null and reroll_btn.has_method("set_color_from_currency"):
			reroll_btn.set_color_from_currency(RunData.players_data[player_index].gold)
		var items_cont = _get_shop_items_container(player_index)
		if items_cont != null:
			for shop_it in items_cont._shop_items:
				if shop_it != null and is_instance_valid(shop_it) and shop_it.has_method("update_color"):
					shop_it.update_color()

		# Reliable xp/level backstop (see send side). .has() guard keeps compatibility with a host
		# that predates these fields; xp_added refreshes the client's xp bar / level display.
		if player_dict.has("CURRENT_XP"):
			RunData.players_data[player_index].current_xp = player_dict["CURRENT_XP"]
			RunData.players_data[player_index].current_level = player_dict.get("CURRENT_LEVEL", RunData.players_data[player_index].current_level)
			RunData.emit_signal("xp_added", player_dict["CURRENT_XP"], player_dict.get("NEXT_LEVEL_XP", 0), player_index)

		# Host-authoritative stats for ALL players (see send side): store on the Utils
		# extension, whose get_stat serves them to every stats panel. This includes our
		# OWN player: a client's local RunData never applies item effects (host does;
		# only gold/xp echo back), so the local view goes stale after every buy. The
		# overrides are cleared at round start so combat never reads frozen values.
		if player_dict.has("STATS") and not steam_connection.is_host():
			var remote_stats = {}
			for stat_key in player_dict["STATS"]:
				remote_stats[Keys.generate_hash(stat_key)] = player_dict["STATS"][stat_key]
			Utils.remote_player_stats[player_index] = remote_stats
			if BT_VERBOSE:
				print("BTSTATS stored p%d n=%d max_hp=%d armor=%d luck=%d" % [player_index, remote_stats.size(), Utils.get_stat(Keys.generate_hash("stat_max_hp"), player_index), Utils.get_stat(Keys.generate_hash("stat_armor"), player_index), Utils.get_stat(Keys.generate_hash("stat_luck"), player_index)])
			_update_stats(player_index)

		waiting_to_start_shop = false


func _dictionary_for_inventory_item(inventory_element : InventoryElement) -> Dictionary:
	var item_data : ItemData = inventory_element.item
	var item_dict = {
		"ID" : item_data.my_id,
		"NUMBER" : inventory_element.current_number,
	}

	var dlc = ProgressData.get_dlc_data("abyssal_terrors")
	if dlc:
		if item_data.is_cursed:
			item_dict["CURSED"] = true

	return item_dict


func _client_focused_inventory_element(data : Dictionary, player_index : int) -> void:
	var focused_element = _focus_inventory_item_for_dictionary(data, player_index)

	is_self_call = true
	Utils.get_focus_emulator(player_index).focused_control = focused_element


func _dictionary_for_focus_inventory_element(element: InventoryElement, player_index : int) -> Dictionary:
	var gear_container : PlayerGearContainer = _get_gear_container(player_index)

	var weapons : Array = gear_container.weapons_container._elements.get_children()
	for weapon_index in weapons.size():
		if element == weapons[weapon_index]:
			return {
				"TYPE" : "WEAPON",
				"INDEX" : weapon_index
			}

	var items : Array = gear_container.items_container._elements.get_children()
	for item_index in items.size():
		if element == items[item_index]:
			return {
				"TYPE" : "ITEM",
				"INDEX" : item_index
			}

	return {}


func _focus_inventory_item_for_dictionary(item_dict : Dictionary, player_index : int) -> Control:
	var gear_container : PlayerGearContainer = _get_gear_container(player_index)

	var focus_type = item_dict["TYPE"]
	if focus_type == "WEAPON":
		var weapon_index = item_dict["INDEX"]
		if weapon_index < gear_container.weapons_container._elements.get_children().size():
			return gear_container.weapons_container._elements.get_children()[weapon_index]
	elif focus_type == "ITEM":
		return gear_container.items_container._elements.get_children()[item_dict["INDEX"]]
	elif focus_type == "GO":
		return _get_go_button(player_index)
	elif focus_type == "REROLL":
		return _get_reroll_button(player_index)
	elif focus_type == "SHOP_ITEM":
		var shop_item : ShopItem = _shop_item_for_string(item_dict["ID"], player_index)
		if shop_item:
			return shop_item._button
	else:
		print("ERR - Focusing inventgory element of unknown type ", item_dict)

	print("ERR - failed to found focus for dict ", item_dict, " ", player_index)
	return null


func _inventory_item_for_dictionary(item_dict : Dictionary) -> ItemData:
	var query_id = item_dict["ID"]

	var result
	for item in ItemService.items:
		if item.my_id == query_id:
			result = item.duplicate()

	for character in ItemService.characters:
		if character.my_id == query_id:
			result = character.duplicate()

	var dlc = ProgressData.get_dlc_data("abyssal_terrors")
	if dlc:
		if item_dict.has("CURSED") and item_dict["CURSED"]:
			result.is_cursed = true

	return result


func _dictionary_for_shop_item(shop_item : Array) -> Dictionary:
	return {
		"ID" : shop_item[0].my_id,
		"WAVE_VALUE": shop_item[1],
	}


func _shop_item_for_dictionary(shop_item_dict : Dictionary) -> Array:
	var item_element

	var query_id = shop_item_dict["ID"]
	for item in ItemService.items:
		if item.my_id == query_id:
			item_element = item.duplicate()
	for weapon in ItemService.weapons:
		if weapon.my_id == query_id:
			item_element = weapon.duplicate()

	var abyssal_dlc = ProgressData.get_dlc_data("abyssal_terrors")
	if abyssal_dlc:
		if shop_item_dict.has("CURSED") and shop_item_dict["CURSED"]:
			item_element.is_cursed = true

	return [item_element, shop_item_dict["WAVE_VALUE"]]


func _dictionary_for_weapon(weapon_data : WeaponData) -> Dictionary:
	var weapon_dict = {
		"ID" : weapon_data.my_id
	}

	var dlc = ProgressData.get_dlc_data("abyssal_terrors")
	if dlc:
		if weapon_data.is_cursed:
			weapon_dict["CURSED"] = true

	return weapon_dict


func _weapon_for_dictionary(weapon_dict : Dictionary) -> WeaponData:
	var query_id = weapon_dict["ID"]

	var result
	for weapon in ItemService.weapons:
		if weapon.my_id == query_id:
			result = weapon.duplicate()

	var dlc = ProgressData.get_dlc_data("abyssal_terrors")
	if dlc and result:
		if weapon_dict.has("CURSED") and weapon_dict["CURSED"]:
			result.is_cursed = true

	return result


func _string_for_weapon(weapon_data : WeaponData) -> String:
	return weapon_data.my_id


func _weapon_for_string(weapon_string : String, player_index : int) -> WeaponData:
	for element in _get_gear_container(player_index).weapons_container._elements.get_children():
		if _string_for_weapon(element.item) == weapon_string:
			return element.item
	return null


func _string_for_shop_item(shop_item : ShopItem) -> String:
	return shop_item.item_data.my_id


func _shop_item_for_string(shop_item_string : String, player_index : int) -> ShopItem:
	for item in _get_shop_items_container(player_index).get_children():
		if not item is ShopItem:
			continue
		if item.item_data.my_id == shop_item_string:
			return item

	return null


func fill_shop_items(player_locked_items: Array, player_index: int, just_entered_shop: bool = false) -> void:
	if $"/root/BrotogetherOptions".in_multiplayer_game:
		if $"/root/SteamConnection".is_host():
			.fill_shop_items(player_locked_items, player_index, just_entered_shop)
	else:
		.fill_shop_items(player_locked_items, player_index, just_entered_shop)


func _focus_dictionary_for_player(player_index : int) -> Dictionary:
	var focused_control : Control = Utils.get_focus_emulator(player_index).focused_control
	for shop_item in _get_shop_items_container(player_index).get_children():
		if not shop_item is ShopItem:
			continue
		if shop_item._button == focused_control:
			return {
				"TYPE" : "SHOP_ITEM",
				"ID" : _string_for_shop_item(shop_item)
			}

	var gear_container : PlayerGearContainer = _get_gear_container(player_index)
	var weapons : Array = gear_container.weapons_container._elements.get_children()
	for weapon_index in weapons.size():
		if focused_control == weapons[weapon_index]:
			return {
				"TYPE" : "WEAPON",
				"INDEX" : weapon_index
			}

	var items : Array = gear_container.items_container._elements.get_children()
	for item_index in items.size():
		if focused_control == items[item_index]:
			return {
				"TYPE" : "ITEM",
				"INDEX" : item_index
			}

	if focused_control == _get_go_button(player_index):
		return {
			"TYPE" : "GO",
		}

	if focused_control == _get_reroll_button(player_index):
		return {
			"TYPE" : "REROLL",
		}

	return {}


func _set_client_focus_for_player(focus_dict : Dictionary, player_index : int) -> void:
	if not focus_dict.has("TYPE"):
		print("ERR - unkown client focus ", player_index, " ", focus_dict)
		return

	var focus_control = _focus_inventory_item_for_dictionary(focus_dict, player_index)
	if focus_control != null and is_instance_valid(focus_control):
		var focus_type : String = focus_dict["TYPE"]
		if focus_type in ["SHOP_ITEM", "ITEM", "WEAPON"]:
			is_self_call = true
		Utils.get_focus_emulator(player_index).focused_control = focus_control
	else:
		print("ERR - Invalid focus dict", focus_dict, " ", player_index)


# Process time check for focusing reroll or go buttons which don't have
# exisiting connected functions
func _check_for_focus_change() -> void:
	var player_index : int = steam_connection.get_my_index()
	var focused_control = Utils.get_focus_emulator(player_index).focused_control

	if focused_control == _get_reroll_button(player_index):
		if not focusing_reroll_button and not waiting_to_start_shop:
			steam_connection.shop_focus_inventory_element(_focus_dictionary_for_player(player_index))
		focusing_reroll_button = true
	else:
		focusing_reroll_button = false

	if focused_control == _get_go_button(player_index):
		if not focusing_go_button and not waiting_to_start_shop:
			steam_connection.shop_focus_inventory_element(_focus_dictionary_for_player(player_index))
		focusing_go_button = true
	else:
		focusing_go_button = false


func _client_shop_reroll(player_index : int) -> void:
	_on_RerollButton_pressed(player_index)


func _on_RerollButton_pressed(player_index: int)->void :
	if in_multiplayer_game:
		if steam_connection.is_host():
			._on_RerollButton_pressed(player_index)
		steam_connection.shop_reroll(player_index)
	else:
		._on_RerollButton_pressed( player_index)


# A member left while in the shop: if everyone still here already pressed GO, the host moves on.
func _on_player_left_run(_player_index : int) -> void:
	if not in_multiplayer_game or not steam_connection.is_host() or get_tree().paused:
		return
	for i in RunData.get_player_count():
		if not _player_pressed_go_button[i] and not steam_connection.left_players.has(i):
			return
	RunData.current_wave += 1
	steam_connection.leave_shop()
	var _error = get_tree().change_scene(MenuData.game_scene)
