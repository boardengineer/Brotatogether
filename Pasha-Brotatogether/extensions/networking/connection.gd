extends Node

# Connection interface
func send_state(_game_state:Dictionary) -> void:
	pass

func send_start_game(_game_info:Dictionary) -> void:
	pass

func send_display_floating_text(_text_info:Dictionary) -> void:
	pass

func send_display_hit_effect(_effect_info:Dictionary) -> void:
	pass

func send_enemy_death(_enemy_id:int) -> void:
	pass
	
func send_end_wave() -> void:
	pass
	
func send_flash_enemy(_enemy_id:int) -> void:
	pass
	
func send_flash_neutral(_neutral_id:int) -> void:
	pass
	
func send_client_position(_client_position: Dictionary) -> void:
	pass
