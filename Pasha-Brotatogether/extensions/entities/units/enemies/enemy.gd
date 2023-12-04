extends Enemy

# Called when the node enters the scene tree for the first time.
func _ready():
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return
	
	var game_controller = $"/root/GameController"
	if game_controller.is_coop() and game_controller.is_host:
		var data_node = load("res://mods-unpacked/Pasha-Brotatogether/networking/data_node.gd").new()
		data_node.set_name("data_node")
		var network_id = game_controller.id_count
		game_controller.id_count = network_id + 1
		data_node.network_id = network_id
		add_child(data_node)

func take_damage(value:int, hitbox:Hitbox = null, dodgeable:bool = true, armor_applied:bool = true, custom_sound:Resource = null, base_effect_scale:float = 1.0) -> Array:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return .take_damage(value, hitbox, dodgeable, armor_applied, custom_sound, base_effect_scale)
		
	var game_controller = $"/root/GameController"
	if not game_controller.is_host:
			return [0, 0 ,0]
	
	var result = .take_damage(value, hitbox, dodgeable, armor_applied, custom_sound, base_effect_scale)
	
	var is_dodge = result.size() >= 3 and result[2] 
	game_controller.send_enemy_take_damage(get_network_id(), is_dodge)
	
	return result

func die(knockback_vector:Vector2 = Vector2.ZERO, p_cleaning_up:bool = false) -> void:
	if not $"/root":
		return
	
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.die(knockback_vector, p_cleaning_up)
		return
		
	.die(knockback_vector, p_cleaning_up)
	var game_controller = $"/root/GameController"
	if get_tree():
		if game_controller.is_host:
			game_controller.send_enemy_death(get_network_id())
	
	
func flash() -> void:
	if not $"/root":
		return
	
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.flash()
		return
	
	.flash()
	var game_controller = $"/root/GameController"
	if game_controller.is_host:
		game_controller.send_flash_enemy(get_network_id())

func _on_Hurtbox_area_entered(hitbox:Area2D) -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		._on_Hurtbox_area_entered(hitbox)
		return
	
	var game_controller = $"/root/GameController"
	if game_controller.is_host:
		._on_Hurtbox_area_entered(hitbox)

func get_network_id() -> int:
	if self.has_node("data_node"):
		return get_node("data_node").network_id
	return -1
