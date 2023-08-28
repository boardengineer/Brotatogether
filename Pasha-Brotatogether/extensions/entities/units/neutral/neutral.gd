extends Neutral
class_name NetworkedNeutral

func _ready():
	var game_controller = $"/root/GameController"
	if game_controller and game_controller.game_mode == "shared" and game_controller.is_source_of_truth:
		var data_node = load("res://mods-unpacked/Pasha-Brotatogether/networking/data_node.gd").new()
		data_node.set_name("data_node")
		var network_id = game_controller.id_count
		game_controller.id_count = network_id + 1
		data_node.network_id = network_id
		add_child(data_node)

func _on_Hurtbox_area_entered(hitbox:Area2D)->void :
	var game_controller = $"/root/GameController"
	if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
		return
	._on_Hurtbox_area_entered(hitbox)
	
func on_hurt()->void :
	if not $"/root".has_node("GameController"):
		.on_hurt()
		return
	
	var game_controller = $"/root/GameController"
	if game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
		return
		
	.on_hurt()
	
	for player_id in game_controller.tracked_players:
		var run_data = game_controller.tracked_players[player_id].run_data
		if run_data.effects["one_shot_trees"]:
			die()
			break

func flash()->void :
	var game_controller = $"/root/GameController"
	if game_controller and game_controller.game_mode == "shared" and game_controller.is_source_of_truth:
		game_controller.send_flash_neutral(get_network_id())
	.flash()

func get_network_id() -> int:
	return get_node("data_node").network_id
