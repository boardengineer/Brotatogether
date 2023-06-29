extends PlayerProjectile
class_name NetworkedPlayerProjectile

func _ready():
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.is_source_of_truth:
			var data_node = load("res://mods-unpacked/Pasha-Brotatogether/networking/data_node.gd").new()
			data_node.set_name("data_node")
			var network_id = game_controller.id_count
			game_controller.id_count = network_id + 1
			data_node.network_id = network_id
			add_child(data_node)

func get_network_id() -> int:
	return get_node("data_node").network_id
