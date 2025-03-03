extends "res://projectiles/player_projectile.gd"


func _get_player_index()->int:
	if self.in_multiplayer_game:
		if not self.is_host:
			return 0
	return ._get_player_index() 


func _on_Hitbox_hit_something(thing_hit: Node, damage_dealt: int) -> void :
	if self.in_multiplayer_game:
		if not self.is_host:
			return
	._on_Hitbox_hit_something(thing_hit, damage_dealt)
