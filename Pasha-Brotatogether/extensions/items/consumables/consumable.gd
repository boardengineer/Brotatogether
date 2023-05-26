extends Consumable
class_name NetworkedConsumable

onready var game_controller = $"/root/GameController"
var id

func _ready():
	if game_controller.is_host:
		id = game_controller.id_count
		game_controller.id_count = id + 1
		
func pickup()->void :
	# clients don't get to pick things up
	if game_controller.is_host:
		.pickup()
