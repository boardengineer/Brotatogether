class_name WeaponDataNode
extends Node

var weapon_data: WeaponData
var weapon

func _ready():
	weapon._hitbox.connect("killed_something", self, "on_killed_something")

# mirrors weapon.on_killed_something
func on_killed_something(_thing_killed:Node)->void :
	var run_data_node = $"/root/MultiplayerRunData"
	weapon.nb_enemies_killed_this_wave += 1
	
	for effect in weapon.effects:
		if effect is GainStatEveryKilledEnemiesEffect and weapon.nb_enemies_killed_this_wave % effect.value == 0:
			run_data_node.add_stat(effect.player_id, effect.stat, effect.stat_nb)
