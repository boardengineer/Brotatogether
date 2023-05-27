extends Gold
class_name NetworkedGold

var id
onready var game_controller = $"/root/GameController"

func _ready():
	if game_controller and game_controller.is_source_of_truth:
		id = game_controller.id_count
		game_controller.id_count = id + 1
		
func pickup()->void :
	if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
		return
	# clients don't get to pick things up
	.pickup()
