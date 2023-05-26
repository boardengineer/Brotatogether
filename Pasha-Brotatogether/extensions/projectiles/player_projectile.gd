extends PlayerProjectile
class_name NetworkedPlayerProjectile

var id
onready var game_controller = $"/root/GameController"

func _ready():
	if game_controller.is_host:
		id = game_controller.id_count
		game_controller.id_count = id + 1
