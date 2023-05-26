extends EntityBirth
class_name NetworkedEntityBirth

onready var game_controller = $"/root/GameController"

var id

func _ready():
	if get_tree().is_network_server():
		id = game_controller.id_count
		game_controller.id_count = id + 1
