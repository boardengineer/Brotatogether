extends AttackBehavior

signal shot
signal finished_shooting
signal entered_long_cooldown
signal started_shooting
signal move_unlocked
signal wanted_to_spawn_an_enemy(enemy_scene, position)

# check out all the nothing this enemy will do!
var max_range
var charge_duration
var charge_speed
var long_cooldown = 1.0
var cooldown = 1.0
var _current_cd = 1.0
var number_projectiles


# 1.2: Brachiosaurus.on_state_changed asks its laser phase to pick its evolved variant.
func force_evolution() -> void:
	pass
