extends "res://projectiles/player_projectile.gd"


func _get_player_index()->int:
	if self.in_multiplayer_game:
		if not self.is_host:
			return 0
	return ._get_player_index() 
