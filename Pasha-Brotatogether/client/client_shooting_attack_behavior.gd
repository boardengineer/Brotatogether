extends "res://entities/units/enemies/attack_behaviors/shooting_attack_behavior.gd"

# Client stand-in for a ShootingAttackBehavior. Same do-nothing role as client_attack_behavior.gd,
# but keeps the ShootingAttackBehavior type: 1.2.0.2's BrachiosaurusFoot holds its landing
# shooters in typed onready vars (landShootNormal: ShootingAttackBehavior = $AttackBehaviorNormal),
# so the plain stub left them null on clients (init/shoot on a null instance every stomp).
# Enemy projectiles come from the host's ENEMY_PROJECTILES rows, so this never spawns any.

# client_attack_behavior.gd's extras that ShootingAttackBehavior does not already declare.
signal started_shooting
signal move_unlocked
signal wanted_to_spawn_an_enemy(enemy_scene, position)

var charge_duration
var charge_speed


func force_evolution() -> void:
	pass


func reset() -> void:
	pass


func physics_process(_delta: float) -> void:
	pass


func animation_finished(_anim_name: String) -> void:
	pass


func start_shoot() -> void:
	pass


func shoot() -> void:
	pass
