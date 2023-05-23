extends PlayerProjectile
class_name NetworkedPlayerProjectile

var id

func _ready():
	if get_tree().is_network_server():
		id = $"/root/networking".id_count
		$"/root/networking".id_count = id + 1
