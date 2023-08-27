extends "res://singletons/run_data.gd"

var weapon_paths = {}

func _ready():
	for weapon in ItemService.weapons:
		weapon_paths[weapon.my_id] = weapon.get_path()

func add_weapon(weapon:WeaponData, is_starting:bool = false)->WeaponData:
	if not weapon_paths.has(weapon.my_id):
		weapon_paths[weapon.my_id] = weapon.get_path()
		
	return .add_weapon(weapon, is_starting)

