extends Gold
class_name NetworkedGold

func _ready():
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return
	
	var game_controller = $"/root/GameController"
	if game_controller.is_host:
		var data_node = load("res://mods-unpacked/Pasha-Brotatogether/networking/data_node.gd").new()
		data_node.set_name("data_node")
		var network_id = game_controller.id_count
		game_controller.id_count = network_id + 1
		data_node.network_id = network_id
		add_child(data_node)
		
func pickup() -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.pickup()
		return
	
	var game_controller = $"/root/GameController"
	if game_controller.is_host:
		.pickup()

func get_network_id() -> int:
	return get_node("data_node").network_id
