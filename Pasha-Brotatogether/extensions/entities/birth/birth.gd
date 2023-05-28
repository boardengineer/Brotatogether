extends EntityBirth
class_name NetworkedEntityBirth

var id

func _ready():
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.is_source_of_truth:
			id = game_controller.id_count
			game_controller.id_count = id + 1
