extends "res://singletons/run_data.gd"

var weapon_paths = {}

func add_weapon(weapon:WeaponData, is_starting:bool = false)->WeaponData:
	# This shouldn't be needed?
	
	weapon_paths[weapon.my_id] = weapon.get_path()
	return .add_weapon(weapon, is_starting)

