extends "res://singletons/run_data.gd"


# Declare member variables here. Examples:
var test_var = 420
# var b = "text"

var weapon_paths = {}


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func add_weapon(weapon:WeaponData, is_starting:bool = false)->WeaponData:
	# TODO, this doesn't look right.
	weapon_paths[weapon.my_id] = weapon.get_path()
	var result = .add_weapon(weapon, is_starting)
	var path = weapon.get_path()
	
	result.set_path("res://weapons/melee/cactus_mace/1/cactus_mace_data.tres")
	return result

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
