extends Neutral
class_name NetworkedNeutral

var id

func _ready():
	if get_tree().is_network_server():
		id = $"/root/networking".id_count
		$"/root/networking".id_count = id + 1

func _on_Hurtbox_area_entered(hitbox:Area2D)->void :
	if not get_tree().is_network_server():
		return
	._on_Hurtbox_area_entered(hitbox)
	
func on_hurt()->void :
	if not get_tree().is_network_server():
		return
	.on_hurt()
