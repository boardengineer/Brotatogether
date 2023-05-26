extends Neutral
class_name NetworkedNeutral

var id
onready var game_controller = $"/root/GameController"

func _ready():
	if game_controller.is_host:
		id = game_controller.id_count
		game_controller.id_count = id + 1

func _on_Hurtbox_area_entered(hitbox:Area2D)->void :
	if not get_tree().is_network_server():
		return
	._on_Hurtbox_area_entered(hitbox)
	
func on_hurt()->void :
	if not get_tree().is_network_server():
		return
	.on_hurt()

func flash()->void :
	if game_controller.is_host:
		game_controller.send_flash_neutral(id)
	.flash()
