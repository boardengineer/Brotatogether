extends Node

# Connection interface
func send_state(game_state:Dictionary) -> void:
	pass

func send_start_game(game_info:Dictionary) -> void:
	pass

func send_display_floating_text(text_info:Dictionary) -> void:
	pass

func send_display_hit_effect(effect_info:Dictionary) -> void:
	pass

func send_enemy_death(enemy_id:int) -> void:
	pass
	
func send_end_wave() -> void:
	pass
	
func send_flash_enemy(enemy_id:int) -> void:
	pass
	
func send_flash_neutral(neutral_id:int) -> void:
	pass
	
func send_client_position(client_position: Dictionary) -> void:
	pass
