extends EntityBirth
class_name NetworkedEntityBirth

onready var game_controller = $"/root/GameController"

var id

func _ready():
	if game_controller and game_controller.is_source_of_truth:
		id = game_controller.id_count
		game_controller.id_count = id + 1
