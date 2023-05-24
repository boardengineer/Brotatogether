extends Shop


func _on_GoButton_pressed()->void :
	if get_tree().is_network_server():
		print_debug("sending start game after shop")
		$"/root/networking".rpc("start_game")
	._on_GoButton_pressed()
