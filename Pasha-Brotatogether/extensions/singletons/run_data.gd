extends "res://singletons/run_data.gd"

var weapon_paths = {}

func add_weapon(weapon:WeaponData, is_starting:bool = false)->WeaponData:
	# TODO, this doesn't look right.
	weapon_paths[weapon.my_id] = weapon.get_path()
	var result = .add_weapon(weapon, is_starting)
	var _path = weapon.get_path()
	return result

