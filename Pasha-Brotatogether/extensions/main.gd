extends "res://main.gd"

var steam_connection
var brotatogether_options
var in_multiplayer_game = false

var player_in_scene = [true, false, false, false]
var waiting_to_start_round = false

func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"
	in_multiplayer_game = brotatogether_options.in_multiplayer_game
	
	if in_multiplayer_game:
		steam_connection.connect("client_status_received", "_client_status_received")
		steam_connection.connect("host_starts_round", "_host_starts_round")
		
		
		call_deferred("multiplayer_ready")


func _process(delta):
	if in_multiplayer_game:
		if waiting_to_start_round:
			if steam_connection.is_host():
				var all_players_entered = true
				for player_index in RunData.get_player_count():
					if not player_in_scene[player_index]:
						all_players_entered = false
						break
				if all_players_entered:
					waiting_to_start_round = false
					_wave_timer.start()


func multiplayer_ready():
	_wave_timer.stop()
	waiting_to_start_round = true
	steam_connection.send_round_start()


func _client_status_received(client_data : Dictionary, player_index : int) -> void:
	if waiting_to_start_round:
		if client_data["CURRENT_SCENE"] == "Main":
			player_in_scene[player_index] = true


func _host_starts_round() -> void:
	waiting_to_start_round = false
	_wave_timer.start()
