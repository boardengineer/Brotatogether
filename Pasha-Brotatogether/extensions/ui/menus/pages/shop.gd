extends Shop


func _on_GoButton_pressed()->void :
	if get_tree().is_network_server():
		$"/root/networking".rpc("start_game")
	._on_GoButton_pressed()
