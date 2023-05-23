extends Gold
class_name NetworkedGold

var id

func _ready():
	if get_tree().is_network_server():
		id = $"/root/networking".id_count
		$"/root/networking".id_count = id + 1
		
func pickup()->void :
	# clients don't get to pick things up
	if get_tree().is_network_server():
		.pickup()
