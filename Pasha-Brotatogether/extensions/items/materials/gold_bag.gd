extends "res://items/materials/gold_bag.gd"

func _on_GoldBag_area_entered(area:Area2D) -> void:
	if not $"/root".has_node("GameController"):
		._on_GoldBag_area_entered(area)
		return
		
	get_tree().get_current_scene().emit_signal("picked_up_multiplayer", area, -1)
