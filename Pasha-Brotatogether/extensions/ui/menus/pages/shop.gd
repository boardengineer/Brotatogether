extends Shop


func _on_GoButton_pressed()->void :
	if $"/root/GameController" and $"/root/GameController".is_host:
		print_debug("sending start game after shop")
		$"/root/networking".rpc("start_game")
	._on_GoButton_pressed()
