extends Enemy
class_name NetworkedEnemy

# Declare member variables here. Examples:
var id

# Called when the node enters the scene tree for the first time.
func _ready():
	if get_tree().is_network_server():
		id = $"/root/networking".id_count
		$"/root/networking".id_count = id + 1

func take_damage(value:int, hitbox:Hitbox = null, dodgeable:bool = true, armor_applied:bool = true, custom_sound:Resource = null, base_effect_scale:float = 1.0)->Array:
	if not get_tree().is_network_server():
		return [0, 0 ,0]
	return .take_damage(value, hitbox, dodgeable, armor_applied, custom_sound, base_effect_scale)

func die(knockback_vector:Vector2 = Vector2.ZERO, p_cleaning_up:bool = false)->void :
	if get_tree():
		if get_tree().is_network_server():
			print_debug("sending death")
			$"/root/networking".rpc("enemy_death", id)
	.die(knockback_vector, p_cleaning_up)

func _on_Hurtbox_area_entered(hitbox:Area2D)->void :
	if not get_tree().is_network_server():
		return
	._on_Hurtbox_area_entered(hitbox)
