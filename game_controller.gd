extends Node

# here they'll be keyed by steam user ids
var tracked_players = {}
var connection

# tracked player info to be used in the multiplayer lobby
var lobby_data = {}

# The id of this player, in direct ip connections this will be 1 for the host.
# in steam connections this will be a steam id against which a username can
# be queried
var self_peer_id

# True iff the user hosted the lobby
var is_host = false

var is_source_of_truth = true
var game_mode = GameMode.VERSUS

enum GameMode {
	VERSUS, 
	COOP, 
}

# A counter user to assign ids for game components
var id_count = 0

var GameStateController = load("res://mods-unpacked/Pasha-Brotatogether/networking/game_state_controller.gd")

const toggle_scene = preload("res://mods-unpacked/Pasha-Brotatogether/ui/toggle.tscn")
const button_scene = preload("res://mods-unpacked/Pasha-Brotatogether/ui/button.tscn")
const explosion_scene = preload("res://projectiles/explosion.tscn")

const MOD_NAME = "Pasha-Brotatogether"
const CONFIG_FILENAME = "user://pasha-brotatogether-options.cfg"
const CONFIG_SECTION = "latest-mp-lobby"

var current_scene_name = ""
var run_updates = false
var disable_pause = false
var back_to_lobby = false
var all_players_ready = true

var batched_deaths = []
var batched_enemy_damage = []
var batched_flash_enemy = []
var batched_floating_text = []
var batched_hit_effects = []

var ready_toggle

var extra_enemies_next_wave = {}
var effects_next_wave = {}
var game_state_controller 

var waiting_for_client_starts = false

signal complete_player_update
signal lobby_info_updated
signal danger_selected(danger_level)
signal character_selected(character_item_data)
signal weapon_selected(weapon_data)
signal upgrade_selected(upgrade_data)
signal item_box_undo(item_data)

func _init():
	game_state_controller = GameStateController.new()
	game_state_controller.parent = self
	add_child(game_state_controller)

func _ready():
	init_lobby_info()

func _process(_delta):
	var scene_name = get_tree().get_current_scene().get_name()
	current_scene_name = scene_name

func init_lobby_info():
	lobby_data = {"players": {}, "first_death_loss": true}
	if is_host:
		lobby_data["players"][self_peer_id] = {"ready": false}

func send_game_state():
	if is_host:
		var buffer = StreamPeerBuffer.new()
		game_state_controller.get_game_state(buffer)
		connection.send_state({"data": buffer.data_array})

func update_game_state(data: PoolByteArray) -> void:
	if get_tree().get_current_scene().get_name() != "ClientMain":
		return
	game_state_controller.update_game_state(data)
	update_health_ui()

func enemy_death(enemy_id):
	game_state_controller.enemy_death(enemy_id)

func flash_neutral(neutral_id):
	game_state_controller.flash_neutral(neutral_id)

func is_coop() -> bool:
	return game_mode == GameMode.COOP

func on_danger_selected(danger) -> void:
	if is_host:
		received_danger_selected(self_peer_id, danger)
	else:
		connection.send_danger_selected(danger)

func received_danger_selected(player_id, danger) -> void:
	lobby_data["players"][player_id]["danger"] = danger
	emit_signal("lobby_info_updated")

func on_character_selected(character) -> void:
	if is_host:
		received_character_selected(self_peer_id, character)
	else:
		connection.send_character_selected(character)

func received_character_selected(player_id, character) -> void:
	lobby_data["players"][player_id]["character"] = character
	lobby_data["players"][player_id].erase("weapon")
	emit_signal("lobby_info_updated")

func on_weapon_selected(weapon) -> void:
	if is_host:
		received_weapon_selected(self_peer_id, weapon)
	else:
		connection.send_weapon_selected(weapon)

func received_weapon_selected(player_id, weapon) -> void:
	lobby_data["players"][player_id]["weapon"] = weapon 
	emit_signal("lobby_info_updated")

func on_mp_lobby_ready_changed(is_ready: bool) -> void:
	if is_host:
		receive_mp_lobby_ready_changed(self_peer_id, is_ready)
	else:
		connection.send_mp_lobby_readied(is_ready)

func receive_mp_lobby_ready_changed(player_id, is_ready: bool) -> void:
	lobby_data["players"][player_id]["ready"] = is_ready
	emit_signal("lobby_info_updated")

func on_upgrade_selected(upgrade_data: Resource) -> void:
	var send_data = {"type": "select_upgrade", "upgrade_data_id": upgrade_data.my_id, "player_id": self_peer_id}
	connection.send_data_to_all(send_data)
	if is_host:
		receive_upgrade_selected(upgrade_data.my_id, self_peer_id)
	else:
		yield(connection, "upgrade_selected")

func receive_upgrade_selected(upgrade_id: String, player_id: int) -> void:
	var run_data_node = $"/root/MultiplayerRunData"
	run_data_node.apply_item_effects(player_id, load(upgrade_id))
	tracked_players[player_id]["upgrades"] = run_data_node.get_player_upgrades(player_id)
	connection.send_tracked_players(tracked_players)

func send_death() -> void:
	disable_pause = false
	run_updates = false
	var send_data = {"type": "death", "player_id": self_peer_id}
	connection.send_data_to_all(send_data)
	if is_host:
		receive_death(self_peer_id)

func receive_death(source_player_id: int) -> void:
	tracked_players[source_player_id]["dead"] = true
	if is_host:
		connection.send_tracked_players(tracked_players)
		check_win()

func check_win() -> void:
	var all_others_dead = true
	var should_end_coop = lobby_data["first_death_loss"]
	for tracked_player_id in tracked_players:
		if tracked_player_id == self_peer_id:
			continue
		if not tracked_players[tracked_player_id].get("dead", false):
			all_others_dead = false
	if all_others_dead or should_end_coop:
		var main = get_tree().get_current_scene()
		main._is_run_won = not is_coop()
		main._is_run_lost = not main._is_run_won
		RunData.run_won = main._is_run_won
		if is_host:
			var rewards = {
				"UNLOCKED_CHARACTERS": ProgressData.get_character_difficulty_info(RunData.current_character.my_id, RunData.current_zone),
				"ACHIEVEMENTS": ["chal_" + RunData.current_character.name.to_lower().replace("character_", "")]
			}
			connection.send_tracked_players({"rewards": rewards, "players": tracked_players})
		main.clean_up_room(false, main._is_run_lost, main._is_run_won)
		if not is_host:
			send_complete_player_request()
		yield(self, "complete_player_update")
		get_tree().change_scene("res://ui/menus/run/end_run.tscn")

func on_item_box_undo_button_pressed(item_data: Resource) -> void:
	var send_data = {"type": "undo_item_box", "item_id": item_data.my_id, "player_id": self_peer_id}
	connection.send_data_to_all(send_data)
	if is_host:
		receive_undo_item_box(self_peer_id, item_data.my_id)

func receive_undo_item_box(player_id: int, item_id: String) -> void:
	var run_data_node = $"/root/MultiplayerRunData"
	run_data_node.remove_item(player_id, item_id)
	connection.send_tracked_players(tracked_players)
	emit_signal("item_box_undo", load(item_id))

func send_complete_player_request():
	var send_data = {"type": "complete_player_update", "player_id": self_peer_id}
	connection.send_data_to_all(send_data)

func receive_complete_player_update(player_id: int):
	emit_signal("complete_player_update")

func update_health_ui():
	var main = get_tree().get_current_scene()
	if main.get_name() == "ClientMain":
		main._ui_gold.on_gold_changed(tracked_players[self_peer_id].get("gold", 0))
		main._ui_bonus_gold.update_value(tracked_players[self_peer_id].get("bonus_gold", 0))
