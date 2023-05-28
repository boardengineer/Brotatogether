extends Enemy

var id

# Called when the node enters the scene tree for the first time.
func _ready():
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared" and game_controller.is_source_of_truth:
			id = game_controller.id_count
			game_controller.id_count = id + 1

func take_damage(value:int, hitbox:Hitbox = null, dodgeable:bool = true, armor_applied:bool = true, custom_sound:Resource = null, base_effect_scale:float = 1.0)->Array:
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
			return [0, 0 ,0]
	return .take_damage(value, hitbox, dodgeable, armor_applied, custom_sound, base_effect_scale)

func die(knockback_vector:Vector2 = Vector2.ZERO, p_cleaning_up:bool = false)->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if get_tree():
			if game_controller and game_controller.game_mode == "shared" and game_controller.is_source_of_truth:
				game_controller.send_enemy_death(id)
	.die(knockback_vector, p_cleaning_up)
	
func flash()->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
			game_controller.send_flash_enemy(id)
	.flash()

func _on_Hurtbox_area_entered(hitbox:Area2D)->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
			return
	._on_Hurtbox_area_entered(hitbox)
