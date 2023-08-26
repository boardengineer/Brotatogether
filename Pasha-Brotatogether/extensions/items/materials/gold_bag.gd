extends "res://items/materials/gold_bag.gd"

func _on_GoldBag_area_entered(area:Area2D) -> void:
	if not $"/root".has_node("GameController"):
		._on_GoldBag_area_entered(area)
		return
		
	area.pickup_multiplayer(-1)
