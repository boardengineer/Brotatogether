extends "res://ui/menus/ingame/upgrades_ui.gd"

# 1.2's wave-end crate chooser lets a player combine, recycle or meca-upgrade an owned weapon
# (to make room for a crate's weapon). Those change RunData, which is host-authoritative: a
# client forwards the action (main.gd _client_weapon_action runs it on the host) instead of
# applying it to its own copy; the result reaches the client with the next shop packet.


func _bt_client() -> bool:
	var opts = get_node_or_null("/root/BrotogetherOptions")
	var sc = get_node_or_null("/root/SteamConnection")
	return opts != null and sc != null and opts.in_multiplayer_game and not sc.is_host()


func _bt_forward(action : String, weapon_data : WeaponData, player_index : int, upgraded_weapon_dict : Dictionary = {}) -> void:
	_popup_manager.reset_focus(player_index)
	var weapon_index = RunData.get_player_weapons(player_index).find(weapon_data)
	if weapon_index >= 0:
		$"/root/SteamConnection".send_main_scene_weapon_action(action, weapon_index, upgraded_weapon_dict)


func _on_weapon_combine_button_pressed(weapon_data: WeaponData, player_index: int) -> void :
	if _bt_client():
		_bt_forward("combine", weapon_data, player_index)
		return
	._on_weapon_combine_button_pressed(weapon_data, player_index)


func _on_weapon_discard_button_pressed(weapon_data: WeaponData, player_index: int) -> void :
	if _bt_client():
		_bt_forward("discard", weapon_data, player_index)
		return
	._on_weapon_discard_button_pressed(weapon_data, player_index)


func _on_weapon_meca_upgrade_selected(weapon_data: WeaponData, upgraded_weapon: WeaponData, player_index: int) -> void :
	if _bt_client():
		_bt_forward("meca", weapon_data, player_index, upgraded_weapon.serialize())
		return
	._on_weapon_meca_upgrade_selected(weapon_data, upgraded_weapon, player_index)
