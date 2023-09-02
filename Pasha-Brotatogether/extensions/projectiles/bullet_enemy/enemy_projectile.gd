extends EnemyProjectile

var network_id

func _ready():
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return
	
	var game_controller = $"/root/GameController"
	if game_controller and game_controller.is_source_of_truth:
		network_id = game_controller.id_count
		game_controller.id_count = network_id + 1
