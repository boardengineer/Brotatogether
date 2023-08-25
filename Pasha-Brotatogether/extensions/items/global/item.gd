extends "res://items/global/item.gd"

signal picked_up_multiplayer(item, player_id)

func pickup_multiplayer(player_id:int)->void :
	emit_signal("picked_up_multiplayer", self, player_id)
	queue_free()
