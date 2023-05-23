extends EntityBirth
class_name NetworkedEntityBirth

var id

func _ready():
	if get_tree().is_network_server():
		id = $"/root/networking".id_count
		$"/root/networking".id_count = id + 1
