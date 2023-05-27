extends Neutral
class_name NetworkedNeutral

var id
onready var game_controller = $"/root/GameController"

func _ready():
	if game_controller and game_controller.is_source_of_truth:
		id = game_controller.id_count
		game_controller.id_count = id + 1

func _on_Hurtbox_area_entered(hitbox:Area2D)->void :
	if game_controller and not game_controller.is_source_of_truth:
		return
	._on_Hurtbox_area_entered(hitbox)
	
func on_hurt()->void :
	if game_controller and not game_controller.is_source_of_truth:
		return
	.on_hurt()

func flash()->void :
	if game_controller and game_controller.is_source_of_truth:
		game_controller.send_flash_neutral(id)
	.flash()
